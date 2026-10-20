/** DSH mux frames wrap stream values in { type: 'next', value: ... }. */
export function streamValue(data) {
  const frame = JSON.parse(data.toString());
  return frame?.value ?? frame;
}
