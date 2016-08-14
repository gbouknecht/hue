#!/usr/bin/swift

import Foundation

enum Error: ErrorType {
    case MissingConfiguration(message:String)
}

class Semaphore {
    let sema = dispatch_semaphore_create(0)

    func signal() {
        dispatch_semaphore_signal(sema)
    }

    func wait() {
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER)
    }
}

class Configuration {
    static let dictPath = NSString(string: "~/.hue.conf.plist").stringByExpandingTildeInPath
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
        let successful = dict.writeToFile(Configuration.dictPath, atomically: true)
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

    func createApiURLWithoutUsernameForRelativeURL(relativeURL: String) throws -> NSURL {
        guard let ipAddress = config.ipAddress else {
            throw Error.MissingConfiguration(message: "Missing ip address")
        }
        return NSURL(string: "http://\(ipAddress)/api/\(relativeURL)")!
    }

    func createApiURLForRelativeURL(relativeURL: String) throws -> NSURL {
        guard let ipAddress = config.ipAddress else {
            throw Error.MissingConfiguration(message: "Missing ip address")
        }
        guard let username = config.username else {
            throw Error.MissingConfiguration(message: "Missing username")
        }
        return NSURL(string: "http://\(ipAddress)/api/\(username)/\(relativeURL)")!
    }

    func doGetWithURL(url: NSURL, successHandler: (NSData) -> Void) throws -> Semaphore {
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = NSURLSession.sharedSession().dataTaskWithURL(url, completionHandler: completionHandler)
        task.resume()
        return semaphore
    }

    func doPostWithURL(url: NSURL, body: AnyObject, successHandler: (NSData) -> Void) throws -> Semaphore {
        let request = try createPostRequestWithURL(url, body: body)
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: completionHandler)
        task.resume()
        return semaphore
    }

    func doDeleteWithURL(url: NSURL, successHandler: (NSData) -> Void = { _ in return }) throws -> Semaphore {
        let request = try createDeleteRequestWithURL(url);
        let semaphore = Semaphore()
        let completionHandler = createCompletionHandlerForURL(url, semaphore: semaphore, successHandler: successHandler)
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: completionHandler)
        task.resume()
        return semaphore
    }

    func createCompletionHandlerForURL(url: NSURL, semaphore: Semaphore, successHandler: (NSData) -> Void) -> (NSData?, NSURLResponse?, NSError?) -> Void {
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

    func createPostRequestWithURL(url: NSURL, body: AnyObject) throws -> NSURLRequest {
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(body, options: [])
        return request
    }

    func createDeleteRequestWithURL(url: NSURL) throws -> NSURLRequest {
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "DELETE"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

class ArgumentsParser {
    func parse1(arguments: [String]) -> (String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0) : nil
    }

    func parse2(arguments: [String]) -> (String, String)? {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let arg0 = args.popFirst(),
        let arg1 = args.popFirst() else {
            return nil
        }
        return args.isEmpty ? (arg0, arg1) : nil
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
        guard let (commandName) = ArgumentsParser().parse1(arguments) where commandName == GetConfigCommand.commandName else {
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
        guard let (commandName, ipAddress) = ArgumentsParser().parse2(arguments) where commandName == SetBridgeIpAddressCommand.commandName else {
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
        guard let (commandName, deviceType) = ArgumentsParser().parse2(arguments) where commandName == SetDeviceTypeCommand.commandName else {
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
        guard let (commandName) = ArgumentsParser().parse1(arguments) where commandName == CreateUserCommand.commandName else {
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
            throw Error.MissingConfiguration(message: "Missing device type")
        }
        let requester = Requester(config: config)
        let url = try requester.createApiURLWithoutUsernameForRelativeURL("")
        semaphore = try requester.doPostWithURL(url, body: ["devicetype": "\(deviceType)"]) {
            (data) in
            let array = try! NSJSONSerialization.JSONObjectWithData(data, options: []) as! NSArray
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
        guard let (commandName, username2) = ArgumentsParser().parse2(arguments) where commandName == DeleteUserCommand.commandName else {
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
        guard let (commandNameFromArgs) = ArgumentsParser().parse1(arguments) where commandNameFromArgs == commandName else {
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
            let object = try! NSJSONSerialization.JSONObjectWithData(data, options: []) as! NSDictionary
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

let config = Configuration()
let args = Process.arguments
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
        GetLightsCommand(config: config, arguments: args)
]

guard let command = commands.filter({ $0.argumentsMatch }).first else {
    let scriptName = String(args[0].characters.split("/").last!)
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
} catch Error.MissingConfiguration(let message) {
    print(message)
} catch {
    print("Unknown error")
}
