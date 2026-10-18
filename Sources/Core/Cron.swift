import Foundation

public struct CronListing: Decodable { public let jobs: [CronJob] }
public struct CronJob: Decodable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public var enabled: Bool
    public let manageable: Bool
    public let revision: String
    public let state: String?
    public let schedule_display: String?
    public let next_run_at: String?
    public let last_run_at: String?
    public let last_status: String?
    public let prompt: String?
    public let latest_execution: ExecutionSnapshot?
    // Sanitized server timeline: status and timestamps only. The native error
    // text, process identity and run output are never sent to this client.
    public struct ExecutionSnapshot: Decodable, Equatable {
        public let id: String?
        public let status: String?
        public let claimed_at: String?
        public let started_at: String?
        public let finished_at: String?
        public let source: String?
    }
}
public enum CronAction: String, CaseIterable {
    case create, edit, enable, disable, delete, run
    public var title: String {
        switch self {
        case .create: return "创建暂停的安排"
        case .edit: return "保存修改"
        case .enable: return "启用安排"
        case .disable: return "暂停安排"
        case .delete: return "删除安排"
        case .run: return "立即调度一次"
        }
    }
    public var warning: String {
        switch self {
        case .create: return "只创建暂停的安排，不会自动执行。结果仅保存在服务器本地，不推送外部平台。"
        case .edit: return "只修改此 App 创建且已暂停的安排；保存后仍需单独启用。"
        case .enable: return "服务器将按计划自动运行，使用该助理配置的工具权限，可能产生模型费用。时间以服务器时区为准。"
        case .disable: return "暂停未来调度；不会停止已经运行的任务。"
        case .delete: return "只删除此 App 创建的安排；不会停止正在运行的任务，也不删除执行输出。"
        case .run: return "请求服务器在下一次调度时运行，并启用这个安排，之后仍会按计划执行。可能使用工具并产生模型费用；请求成功不代表执行完成。"
        }
    }
}
public struct CronCommand {
    public let action: CronAction
    public let job: CronJob?
    public let name: String
    public let prompt: String
    public let schedule: String
    public init(action: CronAction, job: CronJob? = nil, name: String = "", prompt: String = "", schedule: String = "") {
        self.action=action; self.job=job; self.name=name; self.prompt=prompt; self.schedule=schedule
    }
    public var path: String { action == .create ? "cron" : "cron/\(job?.id ?? "invalid")/\(action.rawValue)" }
    public func payload() throws -> Data {
        var payload=["confirm":action.rawValue]
        if action != .create {
            guard let job, job.manageable, job.id.range(of:"^[a-f0-9]{12}$",options:.regularExpression) != nil, !job.revision.isEmpty else {
                throw ClientError.message("此安排仅可查看，请刷新确认权限。")
            }
            if action == .edit && job.enabled { throw ClientError.message("请先暂停安排，再编辑。") }
            payload["revision"]=job.revision
        }
        if action == .create || action == .edit {
            for (key,value,maximum) in [("name",name,100),("prompt",prompt,8000),("schedule",schedule,120)] {
                let text=value.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !text.isEmpty, text.count <= maximum else { throw ClientError.message("名称、任务内容或时间格式为空或过长。") }
                payload[key]=text
            }
        }
        return try JSONEncoder().encode(payload)
    }
}
