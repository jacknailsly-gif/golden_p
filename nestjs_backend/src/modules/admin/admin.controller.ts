import { Controller, Get, Patch, Delete, Param, Body, UseGuards } from '@nestjs/common';
import { SignalsGateway } from '../gateway/signals/signals.gateway';
import { AdminGuard } from './admin.guard';
import { UsersService } from '../users/users.service';

@Controller('api/v1/admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    private readonly signalsGateway: SignalsGateway,
    private readonly usersService: UsersService,
  ) {}

  @Get('metrics')
  getMetrics() {
    return {
      success: true,
      message: 'Metrics fetched successfully',
      data: this.signalsGateway.getMetrics(),
    };
  }

  @Get('users/stats')
  async getUserStats() {
    return {
      success: true,
      data: await this.usersService.getStats(),
    };
  }

  @Get('users')
  async getAllUsers() {
    return {
      success: true,
      data: await this.usersService.findAll(),
    };
  }

  @Patch('users/:id/status')
  async updateUserStatus(@Param('id') id: string, @Body('status') status: string) {
    if (!['active', 'pending', 'inactive'].includes(status)) {
      return { success: false, message: 'Invalid status' };
    }
    const user = await this.usersService.updateStatus(id, status);
    return {
      success: true,
      message: `User status updated to ${status}`,
      data: user,
    };
  }

  @Delete('users/:id')
  async deleteUser(@Param('id') id: string) {
    await this.usersService.deleteUser(id);
    return {
      success: true,
      message: 'User deleted successfully',
    };
  }

  @Get('logs')
  getSystemLogs() {
    // Simulated system logs
    return {
      success: true,
      data: [
        { id: 1, type: 'SECURITY', message: 'Admin logged in', timestamp: new Date().toISOString() },
        { id: 2, type: 'SYSTEM', message: 'WebSocket reconnected', timestamp: new Date().toISOString() },
        { id: 3, type: 'BOT', message: 'Sequence Analyzer started globally', timestamp: new Date().toISOString() }
      ],
    };
  }
}
