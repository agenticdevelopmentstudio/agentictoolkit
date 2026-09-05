import { envConfig, type StatusConfig } from '../../src/config';

/** THE test configuration: the same env adapter the host uses, over this process's
 *  live env — so a test that sets `process.env.X` before or after calling this still
 *  sees its value (envConfig reads through getters, it does not snapshot). */
export const testConfig = (): StatusConfig => envConfig(process.env);
