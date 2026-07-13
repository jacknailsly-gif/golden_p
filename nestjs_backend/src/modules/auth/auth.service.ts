import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthDto } from './dto/auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  async checkUserExists(email: string): Promise<boolean> {
    const existing = await this.usersService.findByEmail(email);
    return !!existing;
  }

  async register(authDto: AuthDto) {
    const existing = await this.usersService.findByEmail(authDto.email);
    if (existing) {
      throw new ConflictException({ success: false, message: 'User already exists' });
    }

    const salt = await bcrypt.genSalt(12);
    const hashedPassword = await bcrypt.hash(authDto.password || '', salt);

    const user = await this.usersService.create({
      email: authDto.email,
      passwordHash: hashedPassword,
      status: 'active', // Changed to active for testing
    });

    return this.generateToken(user);
  }

  async login(authDto: AuthDto) {
    const user = await this.usersService.findByEmail(authDto.email);
    if (!user) {
      throw new UnauthorizedException({ success: false, message: 'Invalid credentials' });
    }

    const isMatch = await bcrypt.compare(authDto.password || '', user.passwordHash);
    if (!isMatch) {
      throw new UnauthorizedException({ success: false, message: 'Invalid credentials' });
    }

    if (user.status === 'pending') {
      throw new UnauthorizedException({ success: false, message: 'Your account is pending approval by an administrator.' });
    }
    if (user.status === 'inactive') {
      throw new UnauthorizedException({ success: false, message: 'Your account has been suspended.' });
    }

    return this.generateToken(user);
  }

  private generateToken(user: any) {
    const payload = { email: user.email, sub: user.id, role: user.role };
    return {
      success: true,
      message: 'Operation successful',
      data: {
        access_token: this.jwtService.sign(payload),
        user: { id: user.id, email: user.email, role: user.role }
      }
    };
  }
}
