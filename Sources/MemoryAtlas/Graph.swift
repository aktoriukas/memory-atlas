import SwiftUI

struct KnowledgeView:View {
    @EnvironmentObject var model:AtlasModel
    @State private var positions:[String:CGPoint]=[:]
    @State private var selected=""
    @State private var zoom:CGFloat=1
    @State private var baseZoom:CGFloat?
    @State private var pan=CGSize.zero
    @State private var drag=CGSize.zero
    var nodes:[[String:Any]] {objects(model.graph["nodes"])}
    var edges:[[String:Any]] {objects(model.graph["edges"])}
    var selectedNode:[String:Any] {nodes.first{string($0["id"])==selected} ?? [:]}
    var body:some View {
        VStack(spacing:0) {
            FilterBar()
            GeometryReader {geo in
                ZStack(alignment:.topLeading) {
                    Canvas {context,size in
                        let transform=CGAffineTransform(translationX:size.width/2+pan.width+drag.width,y:size.height/2+pan.height+drag.height).scaledBy(x:zoom,y:zoom)
                        for edge in edges {
                            if let a=positions[string(edge["from"])],let b=positions[string(edge["to"])] {var path=Path();path.move(to:a.applying(transform));path.addLine(to:b.applying(transform));let active=selected==string(edge["from"]) || selected==string(edge["to"]);context.stroke(path,with:.color((edge["manual"] as? Bool==true ? .orange:atlasAccent).opacity(active ? 0.7:(edge["manual"] as? Bool==true ? 0.5:0.12))),lineWidth:active ? 1.5:0.7)}
                        }
                        for node in nodes {
                            let key=string(node["id"]);guard let point=positions[key] else{continue};let center=point.applying(transform);let type=string(node["type"]);let radius=(type=="memory" || type=="summary" ? CGFloat(4):CGFloat(min(18,8+number(node["count"])/15)))*sqrt(zoom);let color=nodeColor(type)
                            if selected==key{context.fill(Path(ellipseIn:CGRect(x:center.x-radius-5,y:center.y-radius-5,width:(radius+5)*2,height:(radius+5)*2)),with:.color(color.opacity(0.25)))}
                            context.fill(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)),with:.color(color.opacity(selected.isEmpty || selected==key || connected(key) ? 0.95:0.25)))
                            if type != "memory" && type != "summary" || selected==key {let label=String(string(node["label"]).prefix(36));context.draw(Text(label).font(.system(size:selected==key ? 12:10,weight:selected==key ? .semibold:.regular)).foregroundColor(.white.opacity(selected.isEmpty || selected==key ? 0.8:0.5)),at:CGPoint(x:center.x,y:center.y+radius+13))}
                        }
                    }.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:4).onChanged{drag=$0.translation}.onEnded{pan.width += $0.translation.width;pan.height += $0.translation.height;drag = .zero})
                    .simultaneousGesture(SpatialTapGesture().onEnded{tap in let point=CGPoint(x:(tap.location.x-geo.size.width/2-pan.width)/zoom,y:(tap.location.y-geo.size.height/2-pan.height)/zoom);selected=nodes.map{string($0["id"])}.min{distance(positions[$0],point)<distance(positions[$1],point)}.flatMap{distance(positions[$0],point)<25/zoom ? $0:nil} ?? ""})
                    .simultaneousGesture(MagnifyGesture().onChanged{if baseZoom==nil{baseZoom=zoom};zoom=max(0.25,min(3,(baseZoom ?? 1)*$0.magnification))}.onEnded{_ in baseZoom=nil})
                    VStack(alignment:.leading,spacing:8) {Text(model.graph["overview"] as? Bool==true ? "PROJECT OVERVIEW":"KNOWLEDGE NEIGHBORHOOD").font(.system(size:10,weight:.semibold,design:.monospaced));Text("\(nodes.count) nodes · \(edges.count) connections").font(.caption).foregroundStyle(.secondary);if model.graph["limited"] as? Bool==true{Text("Showing 240 recent memories. Narrow filters to explore more.").font(.caption2).foregroundStyle(.secondary)};Picker("Select a node",selection:$selected){Text("Choose a node…").tag("");ForEach(nodes,id:\.selfDescription){node in Text(string(node["label"])).tag(string(node["id"]))}}.labelsHidden().frame(width:220)}.padding(18)
                    VStack{Spacer();HStack(spacing:16){legend("Project",atlasAccent);legend("Concept",.purple);legend("File",.blue);legend("Memory",.gray);legend("Manual",.orange);Spacer();Button{zoom=max(0.25,zoom-0.2)}label:{Image(systemName:"minus.magnifyingglass")};Button{zoom=1;pan = .zero}label:{Image(systemName:"arrow.up.left.and.down.right.magnifyingglass")};Button{zoom=min(3,zoom+0.2)}label:{Image(systemName:"plus.magnifyingglass")}}.padding(18)}
                    if !selected.isEmpty {VStack{HStack{Spacer();VStack(alignment:.leading,spacing:12){HStack{Text(string(selectedNode["type"]).uppercased()).font(.caption2).foregroundStyle(nodeColor(string(selectedNode["type"])));Spacer();Button{selected=""}label:{Image(systemName:"xmark")}.buttonStyle(.plain)};Text(string(selectedNode["label"])).font(.headline).textSelection(.enabled);Text(selected).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled);if selected.hasPrefix("project:"){Button("Explore project"){model.selectKey(selected);selected=""}}else if selected.hasPrefix("observation:") || selected.hasPrefix("summary:"){Button("Open memory"){model.selectKey(selected)}}else{Button("Search this topic"){model.query=string(selectedNode["label"]);model.route="Memories";Task{await model.loadMemories()}}}}.padding(18).frame(width:260).background(atlasPanel,in:RoundedRectangle(cornerRadius:12)).padding(18)};Spacer()}}
                    if nodes.isEmpty{ContentUnavailableView("No graph nodes",systemImage:"point.3.connected.trianglepath.dotted",description:Text("Choose another project or clear your search.")).frame(maxWidth:.infinity,maxHeight:.infinity)}
                }.background(.black.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
            }.padding(.horizontal,28)
        }.task{await model.loadGraph();layout()}.onChange(of:nodes.map{string($0["id"])} ){_,_ in layout()}
    }
    func connected(_ key:String)->Bool {edges.contains{(string($0["from"])==selected && string($0["to"])==key)||(string($0["to"])==selected && string($0["from"])==key)}}
    func nodeColor(_ type:String)->Color {switch type{case "project":return atlasAccent;case "concept":return .purple;case "file":return .blue;case "summary":return .yellow;default:return Color(white:0.72)}}
    func legend(_ text:String,_ color:Color)->some View{HStack(spacing:5){Circle().fill(color).frame(width:6,height:6);Text(text).font(.caption2).foregroundStyle(.secondary)}}
    func distance(_ p:CGPoint?,_ q:CGPoint)->CGFloat{guard let p else{return .infinity};return hypot(p.x-q.x,p.y-q.y)}
    func layout(){
        // ponytail: bounded spring layout, 285 nodes max; neighborhood expansion before a larger solver.
        let ids=nodes.map{string($0["id"])};var points:[String:CGPoint]=[:]
        for (i,id) in ids.enumerated(){let angle=Double(i)*2.399963;let radius=sqrt(Double(i+1))*24;points[id]=CGPoint(x:cos(angle)*radius,y:sin(angle)*radius)}
        for _ in 0..<65 {
            var force=Dictionary(uniqueKeysWithValues:ids.map{($0,CGSize.zero)})
            for i in ids.indices {for j in ids.indices where j>i {let a=points[ids[i]]!,b=points[ids[j]]!;let dx=a.x-b.x,dy=a.y-b.y;let d=max(20,hypot(dx,dy));let strength=min(9,1200/(d*d));force[ids[i]]!.width += dx/d*strength;force[ids[i]]!.height += dy/d*strength;force[ids[j]]!.width -= dx/d*strength;force[ids[j]]!.height -= dy/d*strength}}
            for edge in edges {let a=string(edge["from"]),b=string(edge["to"]);if let p=points[a],let q=points[b]{let dx=q.x-p.x,dy=q.y-p.y,d=max(1,hypot(dx,dy)),strength=(d-85)*0.018;force[a]!.width += dx/d*strength;force[a]!.height += dy/d*strength;force[b]!.width -= dx/d*strength;force[b]!.height -= dy/d*strength}}
            for id in ids{let p=points[id]!,f=force[id]!;points[id]=CGPoint(x:p.x+f.width-p.x*0.003,y:p.y+f.height-p.y*0.003)}
        }
        if ids.count<60, let radius=points.values.map({hypot($0.x,$0.y)}).max(),radius>0 {
            let scale=max(1,min(2,240/radius))
            points=points.mapValues{CGPoint(x:$0.x*scale,y:$0.y*scale)}
        }
        positions=points;selected=""
    }
}
