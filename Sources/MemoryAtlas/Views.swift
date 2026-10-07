import SwiftUI
import Charts

let atlasAccent = Color(red:0.38,green:0.73,blue:0.60)
let atlasBackground = Color(red:0.065,green:0.075,blue:0.085)
let atlasPanel = Color(red:0.105,green:0.12,blue:0.13)

struct Dashboard: View {
    @EnvironmentObject var model: AtlasModel
    @Environment(\.openWindow) var openWindow
    let pages = [("Overview","square.grid.2x2"),("Memories","square.stack"),("Knowledge Graph","point.3.connected.trianglepath.dotted"),("Settings","slider.horizontal.3"),("History","clock.arrow.circlepath")]
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack { Image(systemName:"point.3.connected.trianglepath.dotted").font(.title).foregroundStyle(atlasAccent); VStack(alignment:.leading){Text("MEMORY ATLAS").font(.system(size:13,weight:.bold,design:.monospaced));Text("Your shared knowledge").font(.caption).foregroundStyle(.secondary)} }.padding(.bottom,30).padding(.top,24)
                ForEach(pages,id:\.0) { page in
                    Button { model.route=page.0; Task { if page.0=="Memories" {await model.loadMemories()}; if page.0=="Knowledge Graph" {await model.loadGraph()}; if page.0=="Settings" {await model.loadSettings()} } } label: {
                        Label(page.0,systemImage:page.1).font(.system(size:13,weight:model.route==page.0 ? .semibold:.regular)).frame(maxWidth:.infinity,alignment:.leading).padding(12).background(model.route==page.0 ? atlasAccent.opacity(0.12):.clear,in:RoundedRectangle(cornerRadius:8)).foregroundStyle(model.route==page.0 ? atlasAccent:.secondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                VStack(alignment:.leading,spacing:10) {
                    HStack {Circle().fill(model.online ? atlasAccent:.orange).frame(width:7,height:7);Text(Bridge.demo ? "Demo mode":(model.online ? "Worker connected":"Worker offline")).font(.caption)}
                    Text(Bridge.demo ? "SYNTHETIC EXAMPLES":"LOCAL WORKSPACE").font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary)
                    Text("Claude + Codex").font(.caption)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(atlasPanel,in:RoundedRectangle(cornerRadius:8))
                Text("Memory Atlas · "+(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev")).font(.caption2).foregroundStyle(.tertiary).padding(.top,8)
            }.padding(18).frame(width:215).background(Color.black.opacity(0.17))
            Rectangle().fill(.white.opacity(0.07)).frame(width:1)
            VStack(spacing:0) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:6) { Text(model.route).font(.system(size:27,weight:.semibold));Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    if model.busy {ProgressView().controlSize(.small);Text("Working…").font(.caption)}
                    Menu { Button("All memories as JSON"){model.export("json",filtered:false)};Button("All memories as Obsidian vault"){model.export("markdown",filtered:false)};Divider();Button("Current filters as JSON"){model.export("json",filtered:true)};Button("Current filters as Obsidian vault"){model.export("markdown",filtered:true)} } label: {Label("Export",systemImage:"square.and.arrow.up")}.menuStyle(.borderlessButton).frame(width:92)
                    Button {Task {await model.refresh()}} label:{Image(systemName:"arrow.clockwise")}.help("Refresh now").disabled(model.busy)
                }.padding(28)
                if !model.message.isEmpty { HStack {Image(systemName:"checkmark.circle").foregroundStyle(atlasAccent);Text(model.message);Spacer();Button {model.message=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}.font(.caption).padding(12).background(atlasAccent.opacity(0.08)).padding(.horizontal,28) }
                if !model.pending.isEmpty { HStack {Label("An interrupted edit needs recovery.",systemImage:"exclamationmark.triangle");Spacer();Button("Open History"){model.route="History"}}.padding(12).background(.orange.opacity(0.15)).padding(.horizontal,28) }
                Group {
                    switch model.route {
                    case "Memories": MemoriesView()
                    case "Knowledge Graph": KnowledgeView()
                    case "Settings":SettingsView()
                    case "History":HistoryView()
                    default:OverviewView()
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                HStack {Text("LOCAL STORAGE").font(.system(size:9,design:.monospaced));Text(string(model.info["data_dir"])).font(.caption2);Spacer();if let date=model.lastUpdated {Text("Updated \(date.formatted(date:.omitted,time:.standard)) · every 12s").font(.caption2)} }.foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,12)
            }
        }.background(atlasBackground).preferredColorScheme(.dark).tint(atlasAccent)
        .onAppear {AppDelegate.model=model;AppDelegate.reopen={openWindow(id:"dashboard")}}
        .alert("Memory Atlas",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) {Button("OK"){model.error=nil}} message:{Text(model.error ?? "")}
    }
    var subtitle:String { switch model.route {case "Memories":return "Browse and refine what your assistants remember.";case "Knowledge Graph":return "Explore connections already present in your memories.";case "Settings":return "Control how claude-mem captures and processes knowledge.";case "History":return "Review edits, restore revisions, and recover interrupted saves.";default:return "A living map of everything you’ve learned together."} }
}

struct OverviewView: View {
    @EnvironmentObject var model:AtlasModel
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:14) {
                    stat("OBSERVATIONS",number(model.counts["observation"]).formatted(),"square.stack")
                    stat("SESSION SUMMARIES",number(model.counts["summary"]).formatted(),"text.alignleft")
                    stat("PROJECTS",model.projects.count.formatted(),"folder")
                    stat("DATABASE",ByteCountFormatter.string(fromByteCount:Int64(number(model.info["bytes"])),countStyle:.file),"externaldrive")
                }
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:20) {
                        sectionTitle("Memory activity","Last 30 days")
                        Chart(objects(model.info["activity"]),id:\.selfDescription) { row in
                            BarMark(x:.value("Day",ISO8601DateFormatter().date(from:string(row["day"])+"T00:00:00Z") ?? .distantPast),y:.value("Memories",number(row["count"]))).foregroundStyle(atlasAccent.gradient).cornerRadius(3)
                        }.chartXAxis {AxisMarks(values:.stride(by:.day,count:7)){AxisValueLabel(format:.dateTime.month(.abbreviated).day())}}.frame(height:200)
                    }.padding(22).background(atlasPanel,in:RoundedRectangle(cornerRadius:14))
                    VStack(alignment:.leading,spacing:18) {
                        sectionTitle("Processing","Live worker status")
                        infoRow("Provider",string(model.ai["provider"]).capitalized)
                        infoRow("Authentication",string(model.ai["authMethod"]))
                        infoRow("Model",string(model.info["effective_model"]))
                        infoRow("Queue",queueDescription)
                        infoRow("Semantic index",string(object(model.info["chroma"])["status"]))
                        infoRow("Sessions",number(model.counts["sessions"]).formatted())
                        if !model.online {Button("Start worker"){Task{await model.operation(["op":"start"])}}}
                        ForEach(objects(model.info["cooldowns"]),id:\.selfDescription){q in Text("Quota cooldown: \(string(q["resetAt"]))").font(.caption).foregroundStyle(.orange)}
                    }.frame(width:285).padding(22).background(atlasPanel,in:RoundedRectangle(cornerRadius:14))
                }
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:12) {
                        sectionTitle("Your projects","Open a knowledge neighborhood")
                        ForEach(Array(model.projects.prefix(8)),id:\.selfDescription) {p in
                            Button {model.project=string(p["project"]);model.route="Knowledge Graph";Task{await model.loadGraph()}} label:{HStack{Image(systemName:"folder").foregroundStyle(atlasAccent);Text(string(p["project"])).lineLimit(1);Spacer();Text(number(p["count"]).formatted()).foregroundStyle(.secondary);Image(systemName:"arrow.up.right").font(.caption)}}.buttonStyle(.plain).padding(.vertical,6)
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22).background(atlasPanel,in:RoundedRectangle(cornerRadius:14))
                    VStack(alignment:.leading,spacing:18) {
                        sectionTitle("Connected assistants","One shared local store")
                        ForEach(objects(model.info["sources"]),id:\.selfDescription) {s in HStack{Image(systemName:string(s["source"])=="codex" ? "terminal":"sparkle").foregroundStyle(atlasAccent);Text(string(s["source"]).capitalized);Spacer();Text(number(s["count"]).formatted()).monospacedDigit().foregroundStyle(.secondary)}}
                        Divider()
                        Text("Memories are stored on this Mac. Summarization uses your selected provider; this dashboard makes no AI calls.").font(.caption).foregroundStyle(.secondary)
                        Button("Browse memories"){model.route="Memories";Task{await model.loadMemories()}}
                    }.frame(width:285,alignment:.leading).padding(22).background(atlasPanel,in:RoundedRectangle(cornerRadius:14))
                }
            }.padding(.horizontal,28).padding(.bottom,24)
        }
    }
    var queueDescription:String { let p=object(model.info["processing"]);return p.isEmpty ? "Unavailable":(p["queueDepth"] != nil ? "\(number(p["queueDepth"])) pending":String(describing:p["isProcessing"] ?? p["processing"] ?? "Idle")) }
    func stat(_ title:String,_ value:String,_ icon:String)->some View {VStack(alignment:.leading,spacing:15){HStack{Text(title).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.secondary);Spacer();Image(systemName:icon).foregroundStyle(atlasAccent)};Text(value).font(.system(size:30,weight:.medium,design:.rounded)).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(atlasPanel,in:RoundedRectangle(cornerRadius:12))}
}
extension Dictionary where Key==String,Value==Any {var selfDescription:String {String(describing:self["file"] ?? self["id"] ?? self["day"] ?? self["project"] ?? self["source"] ?? self["provider"] ?? (string(self["from"])+">"+string(self["to"])))}}
func sectionTitle(_ title:String,_ subtitle:String)->some View {VStack(alignment:.leading,spacing:5){Text(title).font(.headline);Text(subtitle).font(.caption).foregroundStyle(.secondary)}}
func infoRow(_ label:String,_ value:String)->some View {HStack(alignment:.top){Text(label).foregroundStyle(.secondary);Spacer();Text(value.isEmpty ? "—":value).multilineTextAlignment(.trailing).textSelection(.enabled)}.font(.caption)}

struct FilterBar:View {
    @EnvironmentObject var model:AtlasModel
    var body:some View {
        HStack(spacing:12) {
            TextField("Search memories…",text:$model.query).textFieldStyle(.roundedBorder).frame(minWidth:150)
            Picker("Project",selection:$model.project){Text("All projects").tag("");ForEach(model.projects,id:\.selfDescription){Text(string($0["project"])).tag(string($0["project"]))}}.labelsHidden().frame(maxWidth:230)
            Picker("Assistant",selection:$model.source){Text("All assistants").tag("");Text("Claude").tag("claude");Text("Codex").tag("codex");Text("Cursor").tag("cursor")}.labelsHidden().frame(width:125)
            Picker("Kind",selection:$model.kind){Text("All memories").tag("");Text("Observations").tag("observation");Text("Summaries").tag("summary")}.labelsHidden().frame(width:125)
            Picker("Date",selection:$model.days){Text("All time").tag(0);Text("Today").tag(1);Text("7 days").tag(7);Text("30 days").tag(30)}.labelsHidden().frame(width:90)
        }.padding(.horizontal,28).padding(.bottom,18)
        .onChange(of:model.query){_,_ in model.filterChanged()}.onChange(of:model.project){_,_ in model.filterChanged()}.onChange(of:model.source){_,_ in model.filterChanged()}.onChange(of:model.kind){_,_ in model.filterChanged()}.onChange(of:model.days){_,_ in model.filterChanged()}
    }
}
struct MemoriesView:View {
    @EnvironmentObject var model:AtlasModel
    var body:some View {
        VStack(spacing:0) {
            FilterBar()
            HSplitView {
                VStack(spacing:0) {
                    ScrollView {LazyVStack(spacing:1) {
                        ForEach(model.records){m in Button{model.select(m)}label:{VStack(alignment:.leading,spacing:8){HStack{Text(m.type.uppercased()).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(atlasAccent);Spacer();Text(m.source.capitalized).font(.caption2).foregroundStyle(.secondary)};Text(m.title).font(.system(size:13,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading);Text(m.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2);HStack{Text(m.project).lineLimit(1);Spacer();Text(m.date,style:.date)}.font(.caption2).foregroundStyle(.tertiary)}.padding(16).background(model.selected?.id==m.id ? atlasAccent.opacity(0.10):.clear)}.buttonStyle(.plain);Divider().opacity(0.4)}
                        if model.hasMore {Button("Load more"){Task{await model.loadMemories(more:true)}}.padding().disabled(model.loading)}
                    }}
                    if model.loading {ProgressView().controlSize(.small).padding(8)}
                    if model.records.isEmpty && !model.loading {ContentUnavailableView("No memories found",systemImage:"magnifyingglass",description:Text("Try another project or search."))}
                }.frame(minWidth:290,idealWidth:350,maxWidth:440)
                if let selected=model.selected {MemoryDetail(memory:selected).id(selected.id).frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)} else {ContentUnavailableView("Select a memory",systemImage:"square.stack",description:Text("Inspect its content, provenance, and links.")).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }.padding(.horizontal,28)
        }
    }
}
struct MemoryDetail:View {
    @EnvironmentObject var model:AtlasModel
    let memory:Memory
    @State private var editing=false
    @State private var linking=false
    @State private var target=""
    @State private var edges:[[String:Any]]=[]
    let observationFields=["subtitle","narrative","text","facts","concepts","files_read","files_modified"]
    let summaryFields=["request","investigated","learned","completed","next_steps","notes"]
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack {Text(memory.id).font(.system(size:11,design:.monospaced)).foregroundStyle(atlasAccent).textSelection(.enabled);Spacer();Button{linking=true}label:{Label("Link",systemImage:"link")};Button{editing=true}label:{Label("Edit",systemImage:"pencil")}.disabled(model.busy || !model.pending.isEmpty || !model.online)}
                Text(memory.title).font(.system(size:24,weight:.semibold)).textSelection(.enabled)
                HStack {Label(memory.project,systemImage:"folder");Text("·");Text(memory.source.capitalized);Text("·");Text(memory.date.formatted())}.font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(memory.kind=="observation" ? observationFields:summaryFields,id:\.self) {key in
                    let value=memory.raw[key]
                    if !string(value).isEmpty || !strings(value).isEmpty { VStack(alignment:.leading,spacing:10){Text(key.replacingOccurrences(of:"_",with:" ").uppercased()).font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary);if let values=value as? [String] {ForEach(Array(values.enumerated()),id:\.offset){_,v in Text("• "+v).font(.callout).textSelection(.enabled)}}else{Text(string(value)).font(.callout).lineSpacing(5).textSelection(.enabled)}} }
                }
                if !edges.isEmpty { VStack(alignment:.leading,spacing:10){Text("MANUAL LINKS").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary);ForEach(edges,id:\.selfDescription){e in let other=string(e["from"])==memory.id ? string(e["to"]):string(e["from"]);HStack{Button(other){model.selectKey(other)};Spacer();Button{Task{_ = await model.operation(["op":"link","from":memory.id,"to":other,"remove":true]);await loadLinks()}}label:{Image(systemName:"link.badge.minus")}.help("Remove link")}}} }
                DisclosureGroup("Provenance") {VStack(spacing:12){infoRow("Session",string(memory.raw["memory_session_id"]));infoRow("Generated by",string(memory.raw["generated_by_model"]));infoRow("Created",string(memory.raw["created_at"]));infoRow("Original project",memory.project)}.padding(.top,12)}.font(.caption)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
        }.background(atlasPanel.opacity(0.5),in:RoundedRectangle(cornerRadius:12)).task{await loadLinks()}
        .sheet(isPresented:$editing){MemoryEditor(memory:memory).environmentObject(model)}
        .sheet(isPresented:$linking){VStack(alignment:.leading,spacing:18){Text("Link this memory").font(.title2);Text("Enter a memory ID from the browser, such as observation:123 or summary:42.").foregroundStyle(.secondary);TextField("Memory ID",text:$target);HStack{Button("Cancel"){linking=false};Spacer();Button("Create link"){Task{if await model.operation(["op":"link","from":memory.id,"to":target.trimmingCharacters(in:.whitespacesAndNewlines)]){linking=false;await loadLinks()}}}.disabled(target.isEmpty || model.busy)}}.padding(28).frame(width:480)}
    }
    func loadLinks() async {if let result=try? await Bridge.run(["op":"links"]){edges=objects(result).filter{string($0["from"])==memory.id || string($0["to"])==memory.id}}}
}
struct MemoryEditor:View {
    @EnvironmentObject var model:AtlasModel
    @Environment(\.dismiss) var dismiss
    let memory:Memory
    @State private var values:[String:String]=[:]
    var fields:[String]{memory.kind=="observation" ? ["title","subtitle","narrative","text","facts","concepts","files_read","files_modified"]:["request","investigated","learned","completed","next_steps","notes"]}
    let lists:Set<String>=["facts","concepts","files_read","files_modified"]
    var body:some View {
        VStack(alignment:.leading,spacing:18){Text("Edit memory").font(.title2);Text("Updates the shared memory. Atlas saves a backup and verifies both search indexes. Capture resumes after the save.").font(.caption).foregroundStyle(.secondary)
            ScrollView {VStack(alignment:.leading,spacing:18){ForEach(fields,id:\.self){key in VStack(alignment:.leading,spacing:6){Text(key.replacingOccurrences(of:"_",with:" ").capitalized+(lists.contains(key) ? " · one item per line":"")).font(.caption).foregroundStyle(.secondary);TextEditor(text:Binding(get:{values[key] ?? ""},set:{values[key]=$0})).font(.system(size:13)).frame(minHeight:key=="title" || key=="subtitle" ? 35:100).padding(7).background(.black.opacity(0.15),in:RoundedRectangle(cornerRadius:6))}}}}
            HStack{Button("Cancel"){dismiss()}.disabled(model.busy);Spacer();if model.busy{ProgressView().controlSize(.small)};Button("Save shared memory"){save()}.buttonStyle(.borderedProminent).disabled(model.busy)}
        }.padding(28).frame(width:710,height:780).onAppear{for key in fields {values[key]=lists.contains(key) ? strings(memory.raw[key]).joined(separator:"\n"):string(memory.raw[key])}}
    }
    func save(){var changes:[String:Any]=[:];for key in fields {let value=values[key] ?? "";if lists.contains(key){let items=value.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty};if items != strings(memory.raw[key]){changes[key]=items}}else if value != string(memory.raw[key]){changes[key]=value}};if changes.isEmpty{dismiss();return};Task{if await model.operation(["op":"edit","kind":memory.kind,"id":memory.numericID,"fingerprint":string(memory.raw["fingerprint"]),"changes":changes]){model.select(memory);dismiss()}}}
}
