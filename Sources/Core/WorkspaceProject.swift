import Foundation

public struct WorkspaceProject: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id=id; self.name=name }
    public static let defaultProject=WorkspaceProject(id:"default",name:"默认工作区")
    public func validate() throws {
        guard id == "default" || (id.count == 34 && id.hasPrefix("p_") && id.dropFirst(2).allSatisfy({ "0123456789abcdef".contains($0) })),
              !name.isEmpty, name.count <= 60 else { throw ClientError.message("无效项目。") }
    }
}
public extension Chat {
    var workspaceProjectID: String { workspaceProject?.id ?? "default" }
    var workspaceProjectName: String { workspaceProject?.name ?? "默认工作区" }
    mutating func bindWorkspace(_ project: WorkspaceProject) throws {
        try project.validate()
        guard run?.terminal != false else { throw ClientError.message("此对话的任务仍在进行，结束后才能切换项目。原任务的工作区不会改变。") }
        workspaceProject=project.id == "default" ? nil : project
    }
}
