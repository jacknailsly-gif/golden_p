import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { GatewayModule } from '../gateway/gateway.module';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [GatewayModule, UsersModule],
  controllers: [AdminController],
})
export class AdminModule {}
