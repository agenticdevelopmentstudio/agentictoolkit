import bcrypt from 'bcryptjs';

// Match the main backend's bcrypt cost.
const COST = 10;

/** A real (cost-COST) bcrypt hash to compare against when no user/passwordHash
 *  exists, so login response timing doesn't reveal whether an email is registered.
 *  Computed once at module load. */
export const DUMMY_PASSWORD_HASH = bcrypt.hashSync('login-timing-equalizer', COST);

export function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, COST);
}

export function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}
