"use client";

import { cn } from "@midday/ui/cn";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@midday/ui/tooltip";
import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { useFormContext } from "react-hook-form";
import { useInvoiceParams } from "@/hooks/use-invoice-params";
import { useTemplateUpdate } from "@/hooks/use-template-update";
import { useTRPC } from "@/trpc/client";
import { Input } from "./input";
import { LabelInput } from "./label-input";

export function InvoiceNo() {
  const {
    watch,
    setError,
    clearErrors,
    formState: { errors },
  } = useFormContext();
  const invoiceNumber = watch("invoiceNumber");
  const trpc = useTRPC();
  const { updateTemplate } = useTemplateUpdate();

  const { invoiceType, invoiceId } = useInvoiceParams();

  const { data } = useQuery(
    trpc.invoice.searchInvoiceNumber.queryOptions(
      {
        query: invoiceNumber,
        // Editing: ignore this invoice's own row, or its current number always
        // reads as a duplicate of itself.
        excludeId: invoiceId ?? undefined,
      },
      {
        // Checked while editing too — the number stays editable after an
        // invoice exists (e.g. drafts created from the tracker), so the
        // duplicate check has to follow it there.
        enabled:
          (invoiceType === "create" || invoiceType === "edit") &&
          invoiceNumber !== "",
        // Never cache the result
        gcTime: 0,
      },
    ),
  );

  useEffect(() => {
    if (data) {
      setError("invoiceNumber", {
        type: "manual",
        message: "Invoice number already exists",
      });
    } else {
      clearErrors("invoiceNumber");
    }
  }, [data]);

  return (
    <div className="flex space-x-1 items-center">
      <div className="flex items-center flex-shrink-0">
        <LabelInput
          name="template.invoiceNoLabel"
          onSave={(value) => {
            updateTemplate({ invoiceNoLabel: value });
          }}
          className="truncate"
        />
        <span className="text-[11px] text-[#878787] flex-shrink-0">:</span>
      </div>

      <TooltipProvider delayDuration={100}>
        <Tooltip>
          <TooltipTrigger asChild>
            <div>
              <Input
                name="invoiceNumber"
                className={cn(
                  "w-28 flex-shrink p-0 border-none text-[11px] h-4.5 overflow-hidden",
                  errors.invoiceNumber ? "text-red-500" : "",
                )}
              />
            </div>
          </TooltipTrigger>
          {errors.invoiceNumber && (
            <TooltipContent className="text-xs px-3 py-1.5">
              <p>Invoice number already exists</p>
            </TooltipContent>
          )}
        </Tooltip>
      </TooltipProvider>
    </div>
  );
}
