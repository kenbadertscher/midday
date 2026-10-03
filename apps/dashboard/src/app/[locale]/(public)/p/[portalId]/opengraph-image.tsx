import { formatAmount } from "@midday/utils/format";
import { ImageResponse } from "next/og";
import { getQueryClient, trpc } from "@/trpc/server";

// Upstream fetched these fonts from https://cdn.midday.ai at render time, so
// generating an OG image reached out to Midday's CDN. Host them yourself and set
// CDN_URL (or NEXT_PUBLIC_CDN_URL) to your own origin.
const FONT_CDN_URL = (
  process.env.CDN_URL ||
  process.env.NEXT_PUBLIC_CDN_URL ||
  ""
).replace(/\/$/, "");

export const contentType = "image/png";

type Props = {
  params: Promise<{ portalId: string }>;
};

export default async function Image({ params }: Props) {
  const { portalId } = await params;
  const queryClient = getQueryClient();

  const data = await queryClient.fetchQuery(
    trpc.customers.getByPortalId.queryOptions({
      portalId,
    }),
  );

  if (!data) {
    return new Response("Not found", { status: 404 });
  }

  const { customer, summary } = data;

  const hedvigSansFont = fetch(
    `${FONT_CDN_URL}/fonts/HedvigSans/HedvigLettersSans-Regular.ttf`,
  ).then((res) => res.arrayBuffer());

  return new ImageResponse(
    <div
      tw="h-full w-full flex flex-col bg-[#0C0C0C] p-16"
      style={{ fontFamily: "hedvig-sans" }}
    >
      {/* Header with logo */}
      <div tw="flex items-center justify-between mb-12">
        <div tw="flex items-center">
          {customer.team.logoUrl && (
            <img
              src={customer.team.logoUrl}
              alt=""
              tw="w-16 h-16 mr-4"
              style={{ objectFit: "contain" }}
            />
          )}
          <div tw="flex flex-col">
            <span tw="text-white text-3xl">{customer.team.name}</span>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div tw="flex flex-col flex-1">
        <span tw="text-[#606060] text-xl mb-2">Customer Portal</span>
        <span tw="text-white text-5xl font-bold mb-12">{customer.name}</span>

        {/* Summary stats */}
        <div tw="flex mt-auto">
          <div tw="flex flex-col mr-16">
            <span tw="text-[#606060] text-lg mb-1">Total</span>
            <span tw="text-white text-3xl">
              {formatAmount({
                amount: summary.totalAmount,
                currency: summary.currency,
              })}
            </span>
          </div>

          <div tw="flex flex-col mr-16">
            <span tw="text-[#606060] text-lg mb-1">Paid</span>
            <span tw="text-white text-3xl">
              {formatAmount({
                amount: summary.paidAmount,
                currency: summary.currency,
              })}
            </span>
          </div>

          <div tw="flex flex-col mr-16">
            <span tw="text-[#606060] text-lg mb-1">Outstanding</span>
            <span tw="text-white text-3xl">
              {formatAmount({
                amount: summary.outstandingAmount,
                currency: summary.currency,
              })}
            </span>
          </div>

          <div tw="flex flex-col">
            <span tw="text-[#606060] text-lg mb-1">Invoices</span>
            <span tw="text-white text-3xl">{summary.invoiceCount}</span>
          </div>
        </div>
      </div>
    </div>,
    {
      width: 1200,
      height: 630,
      fonts: [
        {
          name: "hedvig-sans",
          data: await hedvigSansFont,
          style: "normal",
          weight: 400,
        },
      ],
    },
  );
}
