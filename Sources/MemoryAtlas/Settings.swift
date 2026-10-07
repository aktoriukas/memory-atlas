import SwiftUI
import ServiceManagement

struct SettingsView:View {
    @EnvironmentObject var model:AtlasModel
    @State private var draft:[String:String]=[:]
    @State private var original:[String:String]=[:]
    var provider:String {draft["CLAUDE_MEM_PROVIDER"] ?? "codex"}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:24) {
            sectionTitle("Memory processing","These settings belong to your installed claude-mem worker.")
            GroupBox {
                VStack(alignment:.leading,spacing:18) {
                    Picker("Provider",selection:binding("CLAUDE_MEM_PROVIDER")){Text("Codex · ChatGPT subscription").tag("codex");Text("Claude · subscription or API").tag("claude");Text("Gemini · API key").tag("gemini");Text("OpenRouter · API key").tag("openrouter");Text("OpenAI compatible · API/local").tag("openai-compatible")}
                    switch provider {
                    case "codex":
                        Text("Uses the account signed into Codex CLI. Atlas cannot select or change your paid plan; sign in with the account you want to use.").font(.caption).foregroundStyle(.secondary)
                        field("Model override","CLAUDE_MEM_CODEX_MODEL",hint:"Leave blank to inherit your Codex CLI model")
                        Picker("Reasoning effort",selection:binding("CLAUDE_MEM_CODEX_REASONING_EFFORT")){ForEach(["low","medium","high","xhigh"],id:\.self){Text($0.capitalized).tag($0)}}
                        field("Concurrent agents","CLAUDE_MEM_CODEX_MAX_CONCURRENT_AGENTS")
                        Button("Sign in to Codex…"){model.signIn("codex")}
                    case "claude":
                        Picker("Authentication",selection:binding("CLAUDE_MEM_CLAUDE_AUTH_METHOD")){Text("Claude subscription").tag("subscription");Text("Anthropic API key").tag("api-key")}
                        field("Model","CLAUDE_MEM_MODEL")
                        field("Summary model override","CLAUDE_MEM_TIER_SUMMARY_MODEL",hint:"Blank uses the worker default")
                        Text("Subscription mode uses Claude CLI’s signed-in account. API mode uses the existing Anthropic credential configuration.").font(.caption).foregroundStyle(.secondary)
                        Button("Sign in to Claude…"){model.signIn("claude")}
                    case "gemini":field("Model","CLAUDE_MEM_GEMINI_MODEL");secret("API key","CLAUDE_MEM_GEMINI_API_KEY")
                    case "openrouter":field("Model","CLAUDE_MEM_OPENROUTER_MODEL");secret("API key","CLAUDE_MEM_OPENROUTER_API_KEY");field("Base URL override","CLAUDE_MEM_OPENROUTER_BASE_URL")
                    default:field("Model","CLAUDE_MEM_OPENAI_COMPAT_MODEL");field("Base URL","CLAUDE_MEM_OPENAI_COMPAT_BASE_URL");secret("API key","CLAUDE_MEM_OPENAI_COMPAT_API_KEY");Text("A local model server can keep processing on this Mac. Remote endpoints send content to that provider.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("Memory context") {VStack(alignment:.leading,spacing:16){field("Observations per context","CLAUDE_MEM_CONTEXT_OBSERVATIONS");field("Session summaries per context","CLAUDE_MEM_CONTEXT_SESSION_COUNT");Toggle("Include all assistant sources at session start",isOn:boolean("CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES"));Toggle("Show last session summary",isOn:boolean("CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY"));Text("Explicit shared searches always include both assistants. This controls automatic startup context.").font(.caption).foregroundStyle(.secondary)}.padding(12)}
            HStack{Button("Reload settings"){Task{await model.loadSettings();reset()}};Spacer();Button("Save settings"){save()}.buttonStyle(.borderedProminent).disabled(model.busy || draft==original)}
            Divider()
            GroupBox("This Mac") {VStack(alignment:.leading,spacing:16){Toggle("Start Memory Atlas at login",isOn:Binding(get:{model.loginEnabled},set:{model.launchAtLogin($0)}));infoRow("Memory storage",string(model.info["data_dir"]));infoRow("Active authentication",string(model.ai["authMethod"]));infoRow("Configured model",string(model.info["effective_model"]));infoRow("claude-mem version",string(model.health["version"]));Text("No cloud sync is configured by Atlas. Memory content, exports, backups, and links stay outside the project repository.").font(.caption).foregroundStyle(.secondary);HStack{Button("Open memory folder"){NSWorkspace.shared.open(URL(fileURLWithPath:string(model.info["data_dir"])))};Button("Open login settings"){SMAppService.openSystemSettingsLoginItems()};Spacer();Button("Restart worker"){Task{await model.operation(["op":"restart"])}}.disabled(model.busy || !model.pending.isEmpty)}}.padding(12)}
            Text("Provider changes may need a worker restart. Existing queued tasks resume with the configured provider. Subscription allowance and billing are managed by the provider, and are not measurable from memory counts.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity)}.task{if model.config.isEmpty{await model.loadSettings()};reset()}
    }
    func reset(){draft=model.config.reduce(into:[:]){$0[$1.key]=string($1.value)};original=draft}
    func binding(_ key:String)->Binding<String>{Binding(get:{draft[key] ?? ""},set:{draft[key]=$0})}
    func boolean(_ key:String)->Binding<Bool>{Binding(get:{draft[key]=="true"},set:{draft[key]=$0 ? "true":"false"})}
    func field(_ label:String,_ key:String,hint:String="")->some View {VStack(alignment:.leading,spacing:5){HStack{Text(label).frame(width:195,alignment:.leading);TextField(hint.isEmpty ? label:hint,text:binding(key)).textFieldStyle(.roundedBorder)};if !hint.isEmpty{Text(hint).font(.caption2).foregroundStyle(.secondary).padding(.leading,200)}}}
    func secret(_ label:String,_ key:String)->some View {HStack{Text(label).frame(width:195,alignment:.leading);SecureField("Stored in claude-mem settings",text:binding(key)).textFieldStyle(.roundedBorder)}}
    func save(){var changed:[String:String]=[:];for (key,value) in draft where value != original[key]{changed[key]=value};Task{if await model.operation(["op":"save_settings","changes":changed]){await model.loadSettings();reset();model.message="Settings saved. Restart the worker to apply provider/model changes."}}}
}
struct HistoryView:View {
    @EnvironmentObject var model:AtlasModel
    @State private var revision:[String:Any]?
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack{Text("Every edit keeps its original content and vector documents for undo.").font(.caption).foregroundStyle(.secondary);Spacer();Button("Open backups"){let url=URL(fileURLWithPath:NSHomeDirectory()+"/Library/Application Support/Memory Atlas");NSWorkspace.shared.open(url)}}
            if !model.pending.isEmpty {Button("Recover interrupted edits"){Task{await model.operation(["op":"recover"])}}.buttonStyle(.borderedProminent).disabled(model.busy)}
            if objects(model.info["revisions"]).isEmpty{ContentUnavailableView("No edits yet",systemImage:"clock.arrow.circlepath",description:Text("Your revision history will appear here."))}
            List {ForEach(objects(model.info["revisions"]),id:\.selfDescription){r in HStack{VStack(alignment:.leading,spacing:6){Text(string(r["title"])).lineLimit(2);Text("\(string(r["kind"])):\(number(r["id"])) · \(string(r["time"]))").font(.caption).foregroundStyle(.secondary)};Spacer();Text(string(r["status"]).replacingOccurrences(of:"_",with:" ")).font(.caption).foregroundStyle(.secondary);if string(r["status"])=="complete"{Button("Undo"){revision=r}.disabled(model.busy || !model.pending.isEmpty)}}.padding(.vertical,8)}}.scrollContentBackground(.hidden)
            Text("The latest three full database backups are retained. Per-memory revisions remain available for undo; undo refuses to overwrite later edits.").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal,28).padding(.bottom,20)
        .confirmationDialog("Restore this memory’s content from before the selected edit?",isPresented:Binding(get:{revision != nil},set:{if !$0{revision=nil}}),titleVisibility:.visible){Button("Undo edit"){if let r=revision{Task{await model.operation(["op":"undo","revision":string(r["file"])])}};revision=nil};Button("Cancel",role:.cancel){revision=nil}}
    }
}
