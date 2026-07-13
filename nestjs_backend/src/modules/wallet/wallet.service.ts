import { Injectable, ConflictException, InternalServerErrorException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { Wallet } from './entities/wallet.entity';
import { Transaction } from './entities/transaction.entity';

@Injectable()
export class WalletService {
  constructor(
    @InjectRepository(Wallet)
    private readonly walletRepository: Repository<Wallet>,
    @InjectRepository(Transaction)
    private readonly transactionRepository: Repository<Transaction>,
    private readonly dataSource: DataSource,
  ) {}

  async getBalance(userId: string): Promise<Wallet> {
    let wallet = await this.walletRepository.findOne({ where: { userId } });
    if (!wallet) {
      wallet = this.walletRepository.create({ userId, balance: 0, currency: 'USD' });
      await this.walletRepository.save(wallet);
    }
    return wallet;
  }

  async deposit(userId: string, amount: number, idempotencyKey: string): Promise<Transaction> {
    const queryRunner = this.dataSource.createQueryRunner();
    
    await queryRunner.connect();
    await queryRunner.startTransaction();

    try {
      // 1. Check idempotency key
      if (idempotencyKey) {
        const existingTx = await queryRunner.manager.findOne(Transaction, {
          where: { idempotencyKey },
        });
        if (existingTx) {
          await queryRunner.rollbackTransaction();
          return existingTx;
        }
      }

      // 2. Fetch or create wallet
      // Ideally we would use lock: { mode: 'pessimistic_write' } here for database-level locking.
      // SQLite does not support SELECT FOR UPDATE, but the transaction isolates it appropriately for SQLite.
      let wallet = await queryRunner.manager.findOne(Wallet, {
        where: { userId },
      });

      if (!wallet) {
        wallet = queryRunner.manager.create(Wallet, { userId, balance: 0, currency: 'USD' });
        await queryRunner.manager.save(Wallet, wallet);
      }

      // 3. Create the transaction record first
      const tx = queryRunner.manager.create(Transaction, {
        walletId: wallet.id,
        amount,
        type: 'DEPOSIT',
        status: 'COMPLETED',
        idempotencyKey,
      });
      await queryRunner.manager.save(Transaction, tx);

      // 4. Update the balance securely within the transaction
      wallet.balance = Number(wallet.balance) + Number(amount);
      await queryRunner.manager.save(Wallet, wallet);

      await queryRunner.commitTransaction();
      return tx;
    } catch (err) {
      await queryRunner.rollbackTransaction();
      throw new InternalServerErrorException('Transaction failed: ' + err.message);
    } finally {
      await queryRunner.release();
    }
  }
}
