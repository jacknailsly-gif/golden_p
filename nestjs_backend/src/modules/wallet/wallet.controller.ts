import { Controller, Get, Post, Body, Req, UnauthorizedException, BadRequestException } from '@nestjs/common';
import { WalletService } from './wallet.service';

@Controller('api/v1/wallet')
export class WalletController {
  constructor(private readonly walletService: WalletService) {}

  @Get('balance')
  async getBalance(@Req() req: any) {
    const userId = req.headers['x-user-id'];
    if (!userId) {
      throw new UnauthorizedException('User ID header (x-user-id) is required for this phase');
    }
    const wallet = await this.walletService.getBalance(userId);
    return {
      success: true,
      data: {
        balance: wallet.balance,
        currency: wallet.currency
      }
    };
  }

  @Post('deposit')
  async deposit(@Req() req: any, @Body() body: { amount: number; idempotencyKey: string }) {
    const userId = req.headers['x-user-id'];
    if (!userId) {
      throw new UnauthorizedException('User ID header (x-user-id) is required for this phase');
    }
    
    const { amount, idempotencyKey } = body;
    if (!amount || amount <= 0) {
      throw new BadRequestException('Valid amount is required');
    }
    if (!idempotencyKey) {
      throw new BadRequestException('Idempotency key is required');
    }

    const tx = await this.walletService.deposit(userId, amount, idempotencyKey);
    return {
      success: true,
      data: {
        transactionId: tx.id,
        amount: tx.amount,
        status: tx.status
      }
    };
  }
}
