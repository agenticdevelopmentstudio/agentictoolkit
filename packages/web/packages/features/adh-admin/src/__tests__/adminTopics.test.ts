import { describe, expect, it } from "vitest";
import { ADMIN_PANES } from "../adminPanes";
import { ADMIN_TOPICS, isAdminTopicId } from "../adminTopics";

describe("ADMIN_TOPICS / ADMIN_PANES", () => {
  it("gives every topic a pane", () => {
    for (const topic of ADMIN_TOPICS) {
      expect(ADMIN_PANES[topic.id]).toBeDefined();
    }
  });

  it("has no pane orphaned from a topic", () => {
    const topicIds = new Set(ADMIN_TOPICS.map((t) => t.id));
    for (const id of Object.keys(ADMIN_PANES)) {
      expect(topicIds.has(id as never)).toBe(true);
    }
  });
});

describe("isAdminTopicId", () => {
  it("accepts every real topic id", () => {
    for (const topic of ADMIN_TOPICS) {
      expect(isAdminTopicId(topic.id)).toBe(true);
    }
  });

  it("rejects an id that isn't a topic", () => {
    expect(isAdminTopicId("nope")).toBe(false);
  });
});
