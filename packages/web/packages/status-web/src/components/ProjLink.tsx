import type { CSSProperties, ReactElement, ReactNode } from "react";

/** A row/detail link — opens in a new tab, carries the shared hover-underline
 *  class, and stops its click from bubbling to a row's select handler. */
export function ProjLink({ href, title, style, children }: { href: string; title?: string; style?: CSSProperties; children: ReactNode }): ReactElement {
  return (
    <a className="adh-projlink" href={href} title={title} target="_blank" rel="noopener noreferrer" style={style} onClick={(e) => e.stopPropagation()}>
      {children}
    </a>
  );
}
