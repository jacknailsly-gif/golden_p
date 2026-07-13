import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
  ) {}

  async findByEmail(email: string): Promise<User | undefined> {
    return this.usersRepository.findOne({ where: { email } });
  }

  async create(userDto: Partial<User>): Promise<User> {
    const user = this.usersRepository.create(userDto);
    return this.usersRepository.save(user);
  }

  async findAll(): Promise<Partial<User>[]> {
    return this.usersRepository.find({
      select: {
        id: true,
        email: true,
        role: true,
        status: true,
        createdAt: true,
        updatedAt: true,
      },
      order: { createdAt: 'DESC' },
    });
  }

  async getStats(): Promise<any> {
    const total = await this.usersRepository.count();
    const active = await this.usersRepository.count({ where: { status: 'active' } });
    const pending = await this.usersRepository.count({ where: { status: 'pending' } });
    const inactive = await this.usersRepository.count({ where: { status: 'inactive' } });
    return { total, active, pending, inactive };
  }

  async updateStatus(id: string, status: string): Promise<User> {
    await this.usersRepository.update(id, { status });
    return this.usersRepository.findOne({ where: { id } });
  }

  async deleteUser(id: string): Promise<void> {
    const user = await this.usersRepository.findOne({ where: { id } });
    if (!user) {
      throw new BadRequestException('User not found');
    }
    if (user.role === 'admin') {
      throw new BadRequestException('Cannot delete an admin user.');
    }
    if (user.status === 'active') {
      throw new BadRequestException('Cannot delete an active user. Please suspend them first.');
    }
    await this.usersRepository.delete(id);
  }
}
