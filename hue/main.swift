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
        print("Configuration")
        for (key, value) in dict {
            print("    \(key)=\(value)")
        }
    }
}

protocol Command {
    var argumentsDescription: String { get }
    var argumentsMatch: Bool { get }

    func execute() throws

    func waitUntilFinished()
}

class ConfigCommand: Command {
    static let commandName = "config"

    let config: Configuration
    let argumentsDescription = "\(commandName)"
    let argumentsMatch: Bool

    init(config: Configuration, arguments: [String]) {
        self.config = config
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == ConfigCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = args.isEmpty
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
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == SetBridgeIpAddressCommand.commandName,
        let ipAddress = args.popFirst() else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = args.isEmpty
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
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == SetDeviceTypeCommand.commandName,
        let deviceType = args.popFirst() else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = args.isEmpty
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

    var sema: Semaphore?

    init(config: Configuration, arguments: [String]) {
        self.config = config
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == CreateUserCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = args.isEmpty
    }

    func execute() throws {
        guard argumentsMatch else {
            return
        }
        guard let deviceType = config.deviceType else {
            throw Error.MissingConfiguration(message: "Missing device type")
        }
        let url = try createApiURLWithoutUsernameForRelativeURL("")
        sema = try doPostWithURL(url, body: ["devicetype": "\(deviceType)"]) {
            (data) in
            let dataAsJSON = try! NSJSONSerialization.JSONObjectWithData(data, options: []) as! NSArray
            let object = dataAsJSON.firstObject as! NSDictionary
            if let _ = object["error"] {
                print("Press link button on bridge and then execute this command again within 30 seconds")
            } else if let success = object["success"] as? NSDictionary {
                self.config.username = success["username"] as? String
                self.config.write()
            }
        }
    }

    func createApiURLWithoutUsernameForRelativeURL(relativeURL: String) throws -> NSURL {
        guard let ipAddress = config.ipAddress else {
            throw Error.MissingConfiguration(message: "Missing ip address")
        }
        return NSURL(string: "http://\(ipAddress)/api/\(relativeURL)")!
    }

    func doPostWithURL(url: NSURL, body: AnyObject, successHandler: (NSData) -> Void) throws -> Semaphore {
        let request = try createPostRequestWithURL(url, body: body)
        let sema = Semaphore()
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {
            (data, response, error) in
            if let error = error {
                print("Error calling \(url): \(error.localizedDescription)")
            } else if let data = data {
                successHandler(data)
            } else {
                print("Calling \(url) gives empty response")
            }
            sema.signal()
        }
        task.resume()
        return sema
    }

    func createPostRequestWithURL(url: NSURL, body: AnyObject) throws -> NSURLRequest {
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(body, options: [])
        return request
    }

    func waitUntilFinished() {
        sema?.wait()
    }
}

let config = Configuration()
let args = Process.arguments
let commands: [Command] = [
        ConfigCommand(config: config, arguments: args),
        SetBridgeIpAddressCommand(config: config, arguments: args),
        SetDeviceTypeCommand(config: config, arguments: args),
        CreateUserCommand(config: config, arguments: args)
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
