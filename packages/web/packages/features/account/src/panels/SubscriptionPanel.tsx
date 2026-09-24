"use client";

import { Check } from "lucide-react";

import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { List, ListItem } from "@agenticdevelopertoolkit/ui/components/list";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { Card, CardContent } from "@agenticdevelopertoolkit/ui/components/card";
import { SettingsBody } from "@agentic-toolkit/resource";

interface Plan {
  level: string;
  price: string;
  tagline: string;
  features: string[];
}

// Placeholder pricing/features — billing isn't wired to a backend yet.
const PLANS: Plan[] = [
  {
    level: "Developer",
    price: "Free",
    tagline: "For individuals getting started.",
    features: [
      "1 project",
      "$5 monthly usage credits",
      "Community support",
      "Up to 5 GB storage",
      "Global regions",
    ],
  },
  {
    level: "Pro",
    price: "$20 / mo",
    tagline: "For professionals shipping real work.",
    features: [
      "Unlimited projects",
      "$20 monthly usage credits",
      "Priority support",
      "Up to 1 TB storage",
      "99.99% availability target",
      "30-day log history",
    ],
  },
  {
    level: "Enterprise",
    price: "Custom",
    tagline: "For teams operating at scale.",
    features: [
      "Everything in Pro",
      "SSO / SAML",
      "Dedicated support & SLAs",
      "Audit log retention",
      "Role-based access control",
      "Bring your own cloud",
    ],
  },
];

const OUTLINE_BUTTON =
  "border border-apt-border bg-transparent text-apt-text hover:bg-apt-surface-2";

export function SubscriptionPanel() {
  return (
    <SettingsBody>
      {/* Coming Soon header */}
      <div className="flex items-center gap-3">
        <p className="text-sm text-apt-text-muted">
          Billing and plan management are not yet available.
        </p>
        <Badge variant="blue">Coming Soon</Badge>
      </div>

      {/* Plan cards — displayed for preview only; all actions disabled. */}
      <div className="space-y-4 opacity-60">
        {PLANS.map((plan) => (
          <Card key={plan.level}>
            <CardContent className="flex flex-col gap-4 py-5 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0 space-y-2">
                <div className="flex items-baseline gap-3">
                  <span className="font-semibold text-apt-text">{plan.level}</span>
                  <span className="text-apt-text-muted">{plan.price}</span>
                </div>
                <p className="text-sm text-apt-text-muted">{plan.tagline}</p>
                <List className="grid gap-1.5 border-0 divide-y-0 rounded-none sm:grid-cols-2">
                  {plan.features.map((feature) => (
                    <ListItem
                      key={feature}
                      className="min-h-0 gap-2 px-0 py-0 text-sm text-apt-text-muted"
                    >
                      <Check className="mt-0.5 size-4 shrink-0 text-apt-gold" />
                      <span>{feature}</span>
                    </ListItem>
                  ))}
                </List>
              </div>
              <div className="shrink-0 sm:w-36">
                <Button className={`w-full ${OUTLINE_BUTTON} opacity-60`} disabled>
                  {plan.level === "Developer" ? "Free" : plan.price}
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </SettingsBody>
  );
}
