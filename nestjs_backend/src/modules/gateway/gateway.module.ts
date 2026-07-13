import { Module } from '@nestjs/common';
import { SignalsGateway } from './signals/signals.gateway';

@Module({
  providers: [SignalsGateway],
  exports: [SignalsGateway],
})
export class GatewayModule {}
