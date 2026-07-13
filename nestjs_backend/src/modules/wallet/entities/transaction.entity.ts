import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('transactions')
export class Transaction {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  walletId: string;

  @Column({ type: 'decimal', precision: 18, scale: 8 })
  amount: number;

  @Column({ type: 'varchar', length: 20 })
  type: string; // DEPOSIT | WITHDRAWAL

  @Column({ type: 'varchar', length: 20 })
  status: string; // PENDING | COMPLETED | FAILED

  @Column({ type: 'varchar', length: 100, nullable: true, unique: true })
  idempotencyKey: string;

  @CreateDateColumn()
  createdAt: Date;
}
