import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { User } from '../modules/users/entities/user.entity';
import { Wallet } from '../modules/wallet/entities/wallet.entity';
import { Transaction } from '../modules/wallet/entities/transaction.entity';

export const databaseConfig: TypeOrmModuleOptions = {
  type: 'sqljs',
  location: 'golden_db.sqlite',
  autoSave: true,
  entities: [User, Wallet, Transaction],
  synchronize: true, // Auto-create tables (Dev only)
};
