'use client'

export { CrudTable } from './CrudTable'
export { CrudRecordForm } from './CrudRecordForm'
export { CrudTablePage } from './CrudTablePage'
export type { CrudTablePageProps } from './CrudTablePage'
export { CrudDataBrowser, DefaultCrudShell } from './CrudDataBrowser'
export type {
  CrudDataBrowserProps,
  CrudBrowserSelection,
  CrudShell,
  CrudShellProps,
} from './CrudDataBrowser'
export { useExitGuardChannel } from './useExitGuardChannel'
export { CrudDataView } from './CrudDataView'
export { ApiAffordanceScope } from './ApiAffordanceScope'
export type { CrudDataViewProps } from './CrudDataView'
export { CrudFieldInput, isJsonColumn } from './CrudFieldInput'
export type { CrudFieldInputProps } from './CrudFieldInput'
export {
  isColumnEditable,
  isRelationalColumn,
  isColumnHidden,
  EDITABLE_OVERRIDES,
} from './editability'
export type { EditableMode, EditableOverrides } from './editability'
export { canReadTable, canWriteTable, readableTables } from './exposure'
// For feature packages that publish their OWN table list (e.g. @agentic-toolkit/knowledgebases):
// they need the same viewer this package's browsers gate on, or they list what the server refuses.
export { useViewer } from './viewer'
export type { CrudViewer } from './viewer'
export { CRUD_TABLES } from './generated/table-metadata'
export { CRUD_SCHEMAS } from './schemas'
export { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text'
export { useAction } from '@agenticdevelopertoolkit/ui/hooks/useAction'
export type { ActionState } from '@agenticdevelopertoolkit/ui/hooks/useAction'
export { rowKey } from './useCrudResource'
export { errorMessage } from '@agenticdevelopertoolkit/ui/lib/errors'
export type { CrudColumn, CrudColumnType, CrudExposure, CrudRow, CrudTableMeta } from './types'
