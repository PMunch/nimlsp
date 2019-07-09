import messageenums
# Anything below here comes from the LSP specification
import jsonschema
import json
import options
import sequtils


jsonSchema:
  Message:
    jsonrpc: string

  RequestMessage extends Message:
    id: int or float or string
    "method": string
    params?: any[] or any

  ResponseMessage extends Message:
    id: int or float or string or nil
    "result"?: any
    error?: ResponseError

  ResponseError:
    code: int or float
    message: string
    data: any

  NotificationMessage extends Message:
    "method": string
    params?: any[] or any

  CancelParams:
    id: int or float or string

  Position:
    line: int or float
    character: int or float

  Range:
    start: Position
    "end": Position

  Location:
    uri: string # Note that this is not checked
    "range": Range

  Diagnostic:
    "range": Range
    severity?: int or float
    code?: int or float or string
    source?: string
    message: string
    relatedInformation?: DiagnosticRelatedInformation[]

  DiagnosticRelatedInformation:
    location: Location
    message: string

  Command:
    title: string
    command: string
    arguments?: any[]

  TextEdit:
    "range": Range
    newText: string

  TextDocumentEdit:
    textDocument: VersionedTextDocumentIdentifier
    edits: TextEdit[]

  WorkspaceEdit:
    changes?: any # This is a uri(string) to TextEdit[] mapping
    documentChanges?: TextDocumentEdit[]

  TextDocumentIdentifier:
    uri: string # Note that this is not checked

  TextDocumentItem:
    uri: string
    languageId: string
    version: int or float
    text: string

  VersionedTextDocumentIdentifier extends TextDocumentIdentifier:
    version: int or float or nil
    languageId?: string # SublimeLSP adds this field erroneously

  TextDocumentPositionParams:
    textDocument: TextDocumentIdentifier
    position: Position

  DocumentFilter:
    language?: string
    scheme?: string
    pattern?: string

  MarkupContent:
    kind: string # "plaintext" or "markdown"
    value: string

  InitializeParams:
    processId: int or float or nil
    rootPath?: string or nil
    rootUri: string or nil # String is DocumentUri
    initializationOptions?: any
    capabilities: ClientCapabilities
    trace?: string # 'off' or 'messages' or 'verbose'
    workspaceFolders?: WorkspaceFolder[] or nil

  WorkspaceEditCapability:
    documentChanges?: bool

  DidChangeConfigurationCapability:
    dynamicRegistration?: bool

  DidChangeWatchedFilesCapability:
    dynamicRegistration?: bool

  SymbolKindCapability:
    valueSet?: int # SymbolKind enum

  SymbolCapability:
    dynamicRegistration?: bool
    symbolKind?: SymbolKindCapability

  ExecuteCommandCapability:
    dynamicRegistration?: bool

  WorkspaceClientCapabilities:
    applyEdit?: bool
    workspaceEdit?: WorkspaceEditCapability
    didChangeConfiguration?: DidChangeConfigurationCapability
    didChangeWatchedFiles?: DidChangeWatchedFilesCapability
    symbol?: SymbolCapability
    executeCommand?: ExecuteCommandCapability
    workspaceFolders?: bool
    configuration?: bool

  SynchronizationCapability:
    dynamicRegistration?: bool
    willSave?: bool
    willSaveWaitUntil?: bool
    didSave?: bool

  CompletionItemCapability:
    snippetSupport?: bool
    commitCharactersSupport?: bool
    documentFormat?: string[] # MarkupKind
    deprecatedSupport?: bool

  CompletionItemKindCapability:
    valueSet?: int[] # CompletionItemKind enum

  CompletionCapability:
    dynamicRegistration?: bool
    completionItem?: CompletionItemCapability
    completionItemKind?: CompletionItemKindCapability
    contextSupport?: bool

  HoverCapability:
    dynamicRegistration?: bool
    contentFormat?: string[] # MarkupKind

  SignatureInformationCapability:
    documentationFormat?: string[] # MarkupKind

  SignatureHelpCapability:
    dynamicRegistration?: bool
    signatureInformation?: SignatureInformationCapability

  ReferencesCapability:
    dynamicRegistration?: bool

  DocumentHighlightCapability:
    dynamicRegistration?: bool

  DocumentSymbolCapability:
    dynamicRegistration?: bool
    symbolKind?: SymbolKindCapability

  FormattingCapability:
    dynamicRegistration?: bool

  RangeFormattingCapability:
    dynamicRegistration?: bool

  OnTypeFormattingCapability:
    dynamicRegistration?: bool

  DefinitionCapability:
    dynamicRegistration?: bool

  TypeDefinitionCapability:
    dynamicRegistration?: bool

  ImplementationCapability:
    dynamicRegistration?: bool

  CodeActionCapability:
    dynamicRegistration?: bool

  CodeLensCapability:
    dynamicRegistration?: bool

  DocumentLinkCapability:
    dynamicRegistration?: bool

  ColorProviderCapability:
    dynamicRegistration?: bool

  RenameCapability:
    dynamicRegistration?: bool

  PublishDiagnosticsCapability:
    dynamicRegistration?: bool

  TextDocumentClientCapabilities:
    synchronization?: SynchronizationCapability
    completion?: CompletionCapability
    hover?: HoverCapability
    signatureHelp?: SignatureHelpCapability
    references?: ReferencesCapability
    documentHighlight?: DocumentHighlightCapability
    documentSymbol?: DocumentSymbolCapability
    formatting?: FormattingCapability
    rangeFormatting?: RangeFormattingCapability
    onTypeFormatting?: OnTypeFormattingCapability
    definition?: DefinitionCapability
    typeDefinition?: TypeDefinitionCapability
    implementation?: ImplementationCapability
    codeAction?: CodeActionCapability
    codeLens?: CodeLensCapability
    documentLink?: DocumentLinkCapability
    colorProvider?: ColorProviderCapability
    rename?: RenameCapability
    publishDiagnostics?: PublishDiagnosticsCapability

  ClientCapabilities:
    workspace?: WorkspaceClientCapabilities
    textDocument?: TextDocumentClientCapabilities
    experimental?: any

  WorkspaceFolder:
    uri: string
    name: string

  InitializeResult:
    capabilities: ServerCapabilities

  InitializeError:
    retry: bool

  CompletionOptions:
    resolveProvider?: bool
    triggerCharacters?: string[]

  SignatureHelpOptions:
    triggerCharacters?: string[]

  CodeLensOptions:
    resolveProvider?: bool

  DocumentOnTypeFormattingOptions:
    firstTriggerCharacter: string
    moreTriggerCharacter?: string[]

  DocumentLinkOptions:
    resolveProvider?: bool

  ExecuteCommandOptions:
   commands: string[]

  SaveOptions:
    includeText?: bool

  ColorProviderOptions:
    DUMMY?: nil # This is actually an empty object

  TextDocumentSyncOptions:
    openClose?: bool
    change?: int or float
    willSave?: bool
    willSaveWaitUntil?: bool
    save?: SaveOptions

  StaticRegistrationOptions:
    id?: string

  WorkspaceFolderCapability:
    supported?: bool
    changeNotifications?: string or bool

  WorkspaceCapability:
    workspaceFolders?: WorkspaceFolderCapability

  TextDocumentRegistrationOptions:
    documentSelector: DocumentFilter[] or nil

  TextDocumentAndStaticRegistrationOptions extends TextDocumentRegistrationOptions:
    id?: string

  ServerCapabilities:
    textDocumentSync?: TextDocumentSyncOptions or int or float
    hoverProvider?: bool
    completionProvider?: CompletionOptions
    signatureHelpProvider?: SignatureHelpOptions
    definitionProvider?: bool
    typeDefinitionProvider?: bool or TextDocumentAndStaticRegistrationOptions
    implementationProvider?: bool or TextDocumentAndStaticRegistrationOptions
    referencesProvider?: bool
    documentHighlightProvider?: bool
    documentSymbolProvider?: bool
    workspaceSymbolProvider?: bool
    codeActionProvider?: bool
    codeLensProvider?: CodeLensOptions
    documentFormattingProvider?: bool
    documentRangeFormattingProvider?: bool
    documentOnTypeFormattingProvider?: DocumentOnTypeFormattingOptions
    renameProvider?: bool
    documentLinkProvider?: DocumentLinkOptions
    colorProvider?: bool or ColorProviderOptions or TextDocumentAndStaticRegistrationOptions
    executeCommandProvider?: ExecuteCommandOptions
    workspace?: WorkspaceCapability
    experimental?: any

  InitializedParams:
    DUMMY?: nil # This is actually an empty object

  ShowMessageParams:
    "type": int # MessageType
    message: string

  MessageActionItem:
    title: string

  ShowMessageRequestParams:
    "type": int # MessageType
    message: string
    actions?: MessageActionItem[]

  LogMessageParams:
    "type": int # MessageType
    message: string

  Registration:
    id: string
    "method": string
    registrationOptions?: any

  RegistrationParams:
    registrations: Registration[]

  Unregistration:
    id: string
    "method": string

  UnregistrationParams:
    unregistrations: Unregistration[]

  WorkspaceFoldersChangeEvent:
    added: WorkspaceFolder[]
    removed: WorkspaceFolder[]

  DidChangeWorkspaceFoldersParams:
    event: WorkspaceFoldersChangeEvent

  DidChangeConfigurationParams:
    settings: any

  ConfigurationParams:
    "items": ConfigurationItem[]

  ConfigurationItem:
    scopeUri?: string
    section?: string

  FileEvent:
    uri: string # DocumentUri
    "type": int # FileChangeType

  DidChangeWatchedFilesParams:
    changes: FileEvent[]

  DidChangeWatchedFilesRegistrationOptions:
    watchers: FileSystemWatcher[]

  FileSystemWatcher:
    globPattern: string
    kind?: int # WatchKindCreate (bitmap)

  WorkspaceSymbolParams:
    query: string

  ExecuteCommandParams:
    command: string
    arguments?: any[]

  ExecuteCommandRegistrationOptions:
    commands: string[]

  ApplyWorkspaceEditParams:
    label?: string
    edit: WorkspaceEdit

  ApplyWorkspaceEditResponse:
    applied: bool

  DidOpenTextDocumentParams:
    textDocument: TextDocumentItem

  DidChangeTextDocumentParams:
    textDocument: VersionedTextDocumentIdentifier
    contentChanges: TextDocumentContentChangeEvent[]

  TextDocumentContentChangeEvent:
    range?: Range
    rangeLength?: int or float
    text: string

  TextDocumentChangeRegistrationOptions extends TextDocumentRegistrationOptions:
    syncKind: int or float

  WillSaveTextDocumentParams:
    textDocument: TextDocumentIdentifier
    reason: int # TextDocumentSaveReason

  DidSaveTextDocumentParams:
    textDocument: TextDocumentIdentifier
    text?: string

  TextDocumentSaveRegistrationOptions extends TextDocumentRegistrationOptions:
    includeText?: bool

  DidCloseTextDocumentParams:
    textDocument: TextDocumentIdentifier

  PublishDiagnosticsParams:
    uri: string # DocumentUri
    diagnostics: Diagnostic[]

  CompletionParams extends TextDocumentPositionParams:
    context?: CompletionContext

  CompletionContext:
    triggerKind: int # CompletionTriggerKind
    triggerCharacter?: string

  CompletionList:
    isIncomplete: bool
    "items": CompletionItem[]

  CompletionItem:
    label: string
    kind?: int # CompletionItemKind
    detail?: string
    documentation?: string or MarkupContent
    deprecated?: bool
    preselect?: bool
    sortText?: string
    filterText?: string
    insertText?: string
    insertTextFormat?: int #InsertTextFormat
    textEdit?: TextEdit
    additionalTextEdits?: TextEdit[]
    commitCharacters?: string[]
    command?: Command
    data?: any

  CompletionRegistrationOptions extends TextDocumentRegistrationOptions:
    triggerCharacters?: string[]
    resolveProvider?: bool

  MarkedStringOption:
    language: string
    value: string

  Hover:
    contents: string or MarkedStringOption or string[] or MarkedStringOption[] or MarkupContent
    range?: Range

  SignatureHelp:
    signatures: SignatureInformation[]
    activeSignature?: int or float
    activeParameter?: int or float

  SignatureInformation:
    label: string
    documentation?: string or MarkupContent
    parameters?: ParameterInformation[]

  ParameterInformation:
    label: string
    documentation?: string or MarkupContent

  SignatureHelpRegistrationOptions extends TextDocumentRegistrationOptions:
    triggerCharacters?: string[]

  ReferenceParams extends TextDocumentPositionParams:
    context: ReferenceContext

  ReferenceContext:
    includeDeclaration: bool

  DocumentHighlight:
    "range": Range
    kind?: int # DocumentHighlightKind

  DocumentSymbolParams:
    textDocument: TextDocumentIdentifier

  SymbolInformation:
    name: string
    kind: int # SymbolKind
    deprecated?: bool
    location: Location
    containerName?: string

  CodeActionParams:
    textDocument: TextDocumentIdentifier
    "range": Range
    context: CodeActionContext

  CodeActionContext:
    diagnostics: Diagnostic[]

  CodeLensParams:
    textDocument: TextDocumentIdentifier

  CodeLens:
    "range": Range
    command?: Command
    data?: any

  CodeLensRegistrationOptions extends TextDocumentRegistrationOptions:
    resolveProvider?: bool

  DocumentLinkParams:
    textDocument: TextDocumentIdentifier

  DocumentLink:
    "range": Range
    target?: string # DocumentUri
    data?: any

  DocumentLinkRegistrationOptions extends TextDocumentRegistrationOptions:
    resolveProvider?: bool

  DocumentColorParams:
    textDocument: TextDocumentIdentifier

  ColorInformation:
    "range": Range
    color: Color

  Color:
    red: int or float
    green: int or float
    blue: int or float
    alpha: int or float

  ColorPresentationParams:
    textDocument: TextDocumentIdentifier
    color: Color
    "range": Range

  ColorPresentation:
    label: string
    textEdit?: TextEdit
    additionalTextEdits?: TextEdit[]

  DocumentFormattingParams:
    textDocument: TextDocumentIdentifier
    options: any # FormattingOptions

  #FormattingOptions:
  #  tabSize: int or float
  #  insertSpaces: bool
  #  [key: string]: boolean | int or float | string (jsonschema doesn't support variable key objects)

  DocumentRangeFormattingParams:
    textDocument: TextDocumentIdentifier
    "range": Range
    options: any # FormattingOptions

  DocumentOnTypeFormattingParams:
    textDocument: TextDocumentIdentifier
    position: Position
    ch: string
    options: any # FormattingOptions

  DocumentOnTypeFormattingRegistrationOptions extends TextDocumentRegistrationOptions:
    firstTriggerCharacter: string
    moreTriggerCharacter?: string[]

  RenameParams:
    textDocument: TextDocumentIdentifier
    position: Position
    newName: string
