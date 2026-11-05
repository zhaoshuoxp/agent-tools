import { readAccountLimits } from "../src/provider.mjs";
import { normalizeUsage, describeUsage } from "../src/usage.mjs";

try {
  const snapshot = normalizeUsage(await readAccountLimits());
  console.log(describeUsage(snapshot));
  console.log(`Fetched ${snapshot.buckets.length} usage bucket(s). No model turn was started.`);
} catch (error) {
  console.error(`${error.code ?? "UNAVAILABLE"}: ${error.message}`);
  process.exitCode = 1;
}
