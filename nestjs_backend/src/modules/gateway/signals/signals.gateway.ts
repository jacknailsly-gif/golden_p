import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
import { Injectable } from '@nestjs/common';
import { SubscribeMessage, MessageBody, ConnectedSocket } from '@nestjs/websockets';

@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/ws/signals',
})
@Injectable()
export class SignalsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  // Real-time tracking of active clients
  private activeClients = new Map<string, Socket>();

  constructor(private readonly jwtService: JwtService) {}

  async handleConnection(client: Socket) {
    try {
      const authHeader = client.handshake.headers.authorization || client.handshake.query.token;
      if (!authHeader) {
        client.disconnect();
        return;
      }
      
      const token = typeof authHeader === 'string' ? authHeader.replace('Bearer ', '') : authHeader[0];
      const payload = this.jwtService.verify(token);
      
      this.activeClients.set(payload.email, client);
      console.log(`[WS] Authenticated & Connected: ${payload.email}`);
    } catch (e) {
      console.log('[WS] Unauthorized connection rejected');
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    for (const [email, socket] of this.activeClients.entries()) {
      if (socket.id === client.id) {
        this.activeClients.delete(email);
        console.log(`[WS] Disconnected: ${email}`);
        break;
      }
    }
  }

  // Callable by AI Service or Message Queue (Kafka/Redis)
  broadcastSignal(signal: any) {
    this.server.emit('signal_update', signal);
  }

  // Dashboard Metrics Provider
  getMetrics() {
    return {
      ccu: this.activeClients.size,
      activeUsers: Array.from(this.activeClients.keys()),
    };
  }

  @SubscribeMessage('submit_signal')
  handleSignalSubmission(@MessageBody() data: any, @ConnectedSocket() client: Socket) {
    console.log('[WS] Received signal from client:', data);
    
    // Process the signal or save it
    // Then broadcast to all other users
    this.server.emit('signal_update', {
      ...data,
      global_consensus: true,
      timestamp: new Date().toISOString()
    });
    
    return { status: 'received' };
  }
}
