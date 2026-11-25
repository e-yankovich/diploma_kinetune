// Basic client logging. Errors go to the console with context; never log
// personal data. A remote log service can be plugged in here later.
type Context = Record<string, unknown>;

export const logger = {
  info(message: string, context: Context = {}): void {
    console.info(`[kinetune] ${message}`, context);
  },
  error(message: string, context: Context = {}): void {
    console.error(`[kinetune] ${message}`, context);
  },
};
