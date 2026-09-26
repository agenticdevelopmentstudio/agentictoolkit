// src/site/hubWorkspacePath.ts
import { HUB_ROUTE_SEGMENTS } from "@agentic-toolkit/adh-registry";
var SLUGLESS_APP_SEGMENTS = /* @__PURE__ */ new Set(["home", "settings", "admin"]);
function isRouteSegment(segment) {
  return HUB_ROUTE_SEGMENTS.has(segment.toLowerCase());
}
function firstSegment(pathname) {
  return (pathname || "/").split("/").filter(Boolean)[0];
}
function isHubWorkspacePath(pathname) {
  const first = firstSegment(pathname);
  if (first === void 0) return false;
  return SLUGLESS_APP_SEGMENTS.has(first) || !isRouteSegment(first);
}
function hubWorkspaceSlug(pathname) {
  const first = firstSegment(pathname);
  return first !== void 0 && !isRouteSegment(first) ? first : null;
}
export {
  hubWorkspaceSlug,
  isHubWorkspacePath
};
//# sourceMappingURL=hubWorkspacePath.js.map