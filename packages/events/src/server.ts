// Analytics stripped for self-hosting. See ./client.tsx for context.
//
// Upstream instantiated an OpenPanel client here and posted server-side events
// to https://api.openpanel.dev from the auth callback and webhook routes.

type TrackProperties = Record<string, unknown>;

export const setupAnalytics = async () => {
  return {
    track: (_options: { event: string } & TrackProperties) => {
      // no-op
    },
  };
};
