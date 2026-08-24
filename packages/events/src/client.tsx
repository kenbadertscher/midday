// Analytics stripped for self-hosting.
//
// Upstream wired this to OpenPanel (@openpanel/nextjs), which mounted a
// <Script src="https://openpanel.dev/op1.js"> on every page — unconditionally,
// regardless of whether a client ID was configured — and posted events to
// https://api.openpanel.dev.
//
// The Provider and track() signatures are kept so the ~40 call sites that
// import LogEvents and fire track() still compile. Both are now no-ops.

type TrackProperties = Record<string, unknown>;

const Provider = () => null;

const track = (_options: { event: string } & TrackProperties) => {
  // no-op
};

// Drop-in replacement for @openpanel/nextjs's useOpenPanel(). ~37 dashboard
// components imported that hook directly rather than going through this
// wrapper; they now import from here and their track() calls do nothing.
const useOpenPanel = () => ({
  track: (_event: string, _properties?: TrackProperties) => {
    // no-op
  },
  clear: () => {
    // no-op
  },
});

export type { TrackProperties };
export { Provider, track, useOpenPanel };
