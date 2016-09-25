#!/usr/bin/swift

import Foundation

enum Error: Error {
    case missingConfiguration(message:String)
}

class Semaphore {
    let sema = DispatchSemaphore(value: 0)

    func signal() {
        sema.signal()
    }

    func wait() {
        sema.wait(timeout: DispatchTime.distantFuture)
    }
}

class Configuration {
    static let dictPath = NSString(string: "~/.hue.conf.plist").expandingTildeInPath
    let dict: NSMutableDictionary

    static let ipAddressKey = "IpAddress"
    static let deviceTypeKey = "DeviceType"
    static let usernameKey = "Username"

    var ipAddress: String? {
        get {
            return dict[Configuration.ipAddressKey] as? String
        }
        set {
            dict[Configuration.ipAddressKey] = newValue
        }
    }

    var deviceType: String? {
        get {
            return dict[Configuration.deviceTypeKey] as? String
        }
        set {
            dict[Configuration.deviceTypeKey] = newValue
        }
    }

    var username: String? {
        get {
            return dict[Configuration.usernameKey] as? String
        }
        set {
            dict[Configuration.usernameKey] = newValue
        }
    }

    init() {
        dict = NSMutableDictionary(contentsOfFile: Configuration.dictPath) ?? NSMutableDictionary()
    }

    func write() {
        let successful = dict.write(toFile: Configuration.dictPath, atomically: true)
        if !successful {
            print("Error writing configuration file \(Configuration.dictPath)")
        }
    }

    func printToConsole() {
        for (key, value) in dict {
            print("\(key)=\(value)")
        }
    }
}

class Requester {
    let config: Configuration

    init(config: Configuration) {
        self.config = config
    }

    func createApiURLWithoutUsernameForRelativeURL(_ relativeURL: String) throws -> URL {
        guard let ipAddress = config.ipAddress else {
            throw Error.missingConfiguration(message: "Missing ip address")
        }
        return URL(string: "http://\(ipAddress)/api/\(relativeURL)")!
    }

    func createApiURLForRelativeURL(_ relativeURL: String) throws -> URL {
        guard let ipAddress = config.ipAddress else {
            throw Error.missingConfiguration(message: "Missing ip address")
        }
        let path = try createApiPathForRelativeURL(relativeURL)
        return URL(string: "http://\(ipAddress)\(path)")!
    }

    func createApiPathForRelativeURL(_ relativeURL: String) throws -> String {
        guard let username = config.username else {
            throw Error.missingConfiguration(message: "Missing username")
        }
        return "/api/\(username)/\(relativeURL)"
    }

    func doGetWithURL(_ url: URL, successHandler: @escaping (Data) -> Void) throws -> Semaphore {
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = URLSession.shared.dataTask(with: url, completionHandler: completionHandler as! (Data?, URLResponse?, Error?) -> Void)
        task.resume()
        return semaphore
    }

    func doPostWithURL(_ url: URL, body: AnyObject, successHandler: @escaping (Data) -> Void) throws -> Semaphore {
        let request = try createPostRequestWithURL(url, body: body)
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = URLSession.shared.dataTask(with: request, completionHandler: completionHandler as! (Data?, URLResponse?, Error?) -> Void)
        task.resume()
        return semaphore
    }

    func doDeleteWithURL(_ url: URL, successHandler: @escaping (Data) -> Void = { _ in return }) throws -> Semaphore {
        let request = try createDeleteRequestWithURL(url);
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = URLSession.shared.dataTask(with: request, completionHandler: completionHandler as! (Data?, URLResponse?, Error?) -> Void)
        task.resume()
        return semaphore
    }

    func createCompletionHandlerForURL(_ url: URL, semaphore: Semaphore, successHandler: @escaping (Data) -> Void) -> (Data?, URLResponse?, NSError?) -> Void {
        return {
            (data, response, error) in
            if let error = error {
                print("Error calling \(url): \(error.localizedDescription)")
            } else if let data = data {
                successHandler(data)
            } else {
                print("Calling \(url) gives empty response")
            }
            semaphore.signal()
        }
    }

    func createPostRequestWithURL(_ url: URL, body: AnyObject) throws -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request as URLRequest
    }

    func createDeleteRequestWithURL(_ url: URL) throws -> URLRequest {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request as URLRequest
    }
}

class LightScheduler {
    let config: Configuration

    let localTime: String
    let lightId: String

    init(config: Configuration, localTime: String, lightId: String) {
        self.config = config
        self.localTime = localTime
        self.lightId = lightId
    }

    func createScheduleWithCommandBody(_ body: NSDictionary) throws -> Semaphore {
        let requester = Requester(config: config)
        let url = try requester.createApiURLForRelativeURL("schedules")
        let commandAddress = try requester.createApiPathForRelativeURL("lights/\(lightId)/state")
        let command = ["address": "\(commandAddress)", "method": "PUT", "body": body] as [String : Any]
        return try requester.doPostWithURL(url, body: ["name": "Schedule Light", "command": command, "localtime": localTime]) {
            (data) in
            let array = try! JSONSerialization.jsonObject(with: data, options: []) as! NSArray
            let object = array.firstObject as! NSDictionary
            if let error = object["error"] as? NSDictionary {
                let description = error["description"] as! String
                print("Error creating schedule: \(description)")
            } else if let success = object["success"] as? NSDictionary {
                let id = success["id"] as! String
                print("Created schedule with id \(id)")
            }
        }
    }
}

class ArgumentsParser {
    func parse1(_ arguments: [String]) -> (String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0) : nil
    }

    func parse2(_ arguments: [String]) -> (String, String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst(),
        let arg1 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0, arg1) : nil
    }

    func parse3(_ arguments: [String]) -> (String, String, String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst(),
        let arg1 = args.popFirst(),
        let arg2 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0, arg1, arg2) : nil
    }

    func parse4(_ arguments: [String]) -> (String, String, String, String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst(),
        let arg1 = args.popFirst(),
        let arg2 = args.popFirst(),
        let arg3 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0, arg1, arg2, arg3) : nil
    }
}

protocol Command {
    var argumentsDescription: String { get }
    var argumentsMatch: Bool { get }

    func execute() throws

    func waitUntilFinished()
}

class GetConfigCommand: Command {
    static let commandName = "get-config"

    let config: Configuration
    let argumentsDescription = "\(commandName)"
    let argumentsMatch: Bool

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName) = ArgumentsParser().parse1(arguments) , commandName == GetConfigCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
    }

    func execute() {
        guard argumentsMatch else {
            return
        }
        config.printToConsole()
    }

    func waitUntilFinished() {
    }
}

class SetBridgeIpAddressCommand: Command {
    static let commandName = "set-bridge-ip-address"

    let config: Configuration
    let argumentsDescription = "\(commandName) <ip-address>"
    let argumentsMatch: Bool

    var ipAddress: String?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, ipAddress) = ArgumentsParser().parse2(arguments) , commandName == SetBridgeIpAddressCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.ipAddress = ipAddress
    }

    func execute() {
        guard argumentsMatch else {
            return
        }
        config.ipAddress = ipAddress
        config.write()
    }

    func waitUntilFinished() {
    }
}

class SetDeviceTypeCommand: Command {
    static let commandName = "set-device-type"

    let config: Configuration
    let argumentsDescription = "\(commandName) <device-type>"
    let argumentsMatch: Bool

    var deviceType: String?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, deviceType) = ArgumentsParser().parse2(arguments) , commandName == SetDeviceTypeCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.deviceType = deviceType
    }

    func execute() {
        guard argumentsMatch else {
            return
        }
        config.deviceType = deviceType
        config.write()
    }

    func waitUntilFinished() {
    }
}

class CreateUserCommand: Command {
    static let commandName = "create-user"

    let config: Configuration
    let argumentsDescription = "\(commandName)"
    let argumentsMatch: Bool

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName) = ArgumentsParser().parse1(arguments) , commandName == CreateUserCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        guard let deviceType = config.deviceType else {
            throw Error.missingConfiguration(message: "Missing device type")
        }
        let requester = Requester(config: config)
        let url = try requester.createApiURLWithoutUsernameForRelativeURL("")
        semaphore = try requester.doPostWithURL(url, body: ["devicetype": "\(deviceType)"]) {
            (data) in
            let array = try! JSONSerialization.jsonObject(with: data, options: []) as! NSArray
            let object = array.firstObject as! NSDictionary
            if let _ = object["error"] {
                print("Press link button on bridge and then execute this command again within 30 seconds")
            } else if let success = object["success"] as? NSDictionary {
                self.config.username = success["username"] as? String
                self.config.write()
            }
        }
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

class DeleteUserCommand: Command {
    static let commandName = "delete-user"

    let config: Configuration
    let argumentsDescription = "\(commandName) <username>"
    let argumentsMatch: Bool

    var username2: String?

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, username2) = ArgumentsParser().parse2(arguments) , commandName == DeleteUserCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.username2 = username2
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        let requester = Requester(config: config)
        let url = try requester.createApiURLForRelativeURL("config/whitelist/\(username2!)")
        semaphore = try requester.doDeleteWithURL(url)
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

class GetCommand: Command {
    let config: Configuration
    let argumentsDescription: String
    let argumentsMatch: Bool

    let relativeURL: String

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String], commandName: String, relativeURL: String) {
        self.config = config
        self.argumentsDescription = "\(commandName)"
        self.relativeURL = relativeURL
        guard let (commandNameFromArgs) = ArgumentsParser().parse1(arguments) , commandNameFromArgs == commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        let requester = Requester(config: config)
        let url = try requester.createApiURLForRelativeURL(relativeURL)
        semaphore = try requester.doGetWithURL(url) {
            (data) in
            let object = try! JSONSerialization.jsonObject(with: data, options: []) as! NSDictionary
            print(object)
        }
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

class GetBridgeConfigCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-bridge-config", relativeURL: "config")
    }
}

class GetScenesCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-scenes", relativeURL: "scenes")
    }
}

class GetSchedulesCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-schedules", relativeURL: "schedules")
    }
}

class GetGroupsCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-groups", relativeURL: "groups")
    }
}

class GetSensorsCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-sensors", relativeURL: "sensors")
    }
}

class GetLightsCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-lights", relativeURL: "lights")
    }
}

class GetRulesCommand: GetCommand {
    init(config: Configuration, arguments: [String]) {
        super.init(config: config, arguments: arguments, commandName: "get-rules", relativeURL: "rules")
    }
}

class CreateScheduleLightOn: Command {
    static let commandName = "create-schedule-light-on"

    let config: Configuration
    let argumentsDescription = "\(commandName) <local-time> <light-id> <brightness>"
    let argumentsMatch: Bool

    var localTime: String?
    var lightId: String?
    var brightness: Int?

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, localTime, lightId, brightness) = ArgumentsParser().parse4(arguments) , commandName == CreateScheduleLightOn.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.localTime = localTime
        self.lightId = lightId
        self.brightness = Int(brightness) ?? 254
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        let scheduler = LightScheduler(config: config, localTime: localTime!, lightId: lightId!)
        semaphore = try scheduler.createScheduleWithCommandBody(["on": true, "bri": brightness!])
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

class CreateScheduleLightOff: Command {
    static let commandName = "create-schedule-light-off"

    let config: Configuration
    let argumentsDescription = "\(commandName) <local-time> <light-id>"
    let argumentsMatch: Bool

    var localTime: String?
    var lightId: String?

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, localTime, lightId) = ArgumentsParser().parse3(arguments) , commandName == CreateScheduleLightOff.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.localTime = localTime
        self.lightId = lightId
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        let scheduler = LightScheduler(config: config, localTime: localTime!, lightId: lightId!)
        semaphore = try scheduler.createScheduleWithCommandBody(["on": false])
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

class DeleteSchedule: Command {
    static let commandName = "delete-schedule"

    let config: Configuration
    let argumentsDescription = "\(commandName) <schedule-id>"
    let argumentsMatch: Bool

    var scheduleId: String?

    var semaphore: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        guard let (commandName, scheduleId) = ArgumentsParser().parse2(arguments) , commandName == DeleteSchedule.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
        self.scheduleId = scheduleId
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        let requester = Requester(config: config)
        let url = try requester.createApiURLForRelativeURL("schedules/\(scheduleId!)")
        semaphore = try requester.doDeleteWithURL(url)
    }

    func waitUntilFinished() {
        semaphore?.wait()
    }
}

let config = Configuration()
let args = CommandLine.arguments
let commands: [Command] = [
        GetConfigCommand(config: config, arguments: args),
        SetBridgeIpAddressCommand(config: config, arguments: args),
        SetDeviceTypeCommand(config: config, arguments: args),
        CreateUserCommand(config: config, arguments: args),
        DeleteUserCommand(config: config, arguments: args),
        GetBridgeConfigCommand(config: config, arguments: args),
        GetScenesCommand(config: config, arguments: args),
        GetSchedulesCommand(config: config, arguments: args),
        GetGroupsCommand(config: config, arguments: args),
        GetSensorsCommand(config: config, arguments: args),
        GetLightsCommand(config: config, arguments: args),
        GetRulesCommand(config: config, arguments: args),
        CreateScheduleLightOn(config: config, arguments: args),
        CreateScheduleLightOff(config: config, arguments: args),
        DeleteSchedule(config: config, arguments: args)
]

guard let command = commands.filter({ $0.argumentsMatch }).first else {
    let scriptName = String(args[0].characters.split(separator: "/").last!)
    print("usage: \(scriptName) <command> [<args>]")
    print()
    print("Available commands:")
    print()
    for command in commands {
        print("    \(command.argumentsDescription)")
    }
    exit(1)
}

do {
    try command.execute()
    command.waitUntilFinished()
} catch Error.missingConfiguration(let message) {
    print(message)
} catch {
    print("Unknown error")
}
