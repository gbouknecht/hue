#!/usr/bin/swift

import Foundation

class Configuration {
    static let dictPath = NSString(string: "~/.hue.conf.plist").stringByExpandingTildeInPath
    let dict: NSMutableDictionary

    static let ipAddressKey = "IpAddress"

    var ipAddress: String? {
        get {
            return dict[Configuration.ipAddressKey] as? String
        }
        set {
            dict[Configuration.ipAddressKey] = newValue
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

    func execute()
}

class ConfigCommand: Command {
    static let commandName = "config"

    let argumentsDescription = "\(commandName)"
    let argumentsMatch: Bool

    init(_ arguments: [String]) {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == ConfigCommand.commandName else {
            self.argumentsMatch = false
            return
        }
        self.argumentsMatch = true
    }

    func execute() {
        guard argumentsMatch else {
            return
        }
        Configuration().printToConsole()
    }
}

class SetBridgeIpAddressCommand: Command {
    static let commandName = "set-bridge-ip-address"

    let argumentsDescription = "\(commandName) <ip-address>"
    let argumentsMatch: Bool

    var ipAddress: String?

    init(_ arguments: [String]) {
        var args = ArraySlice(arguments)
        guard
        let _ = args.popFirst(),
        let commandName = args.popFirst() where commandName == SetBridgeIpAddressCommand.commandName,
        let ipAddress = args.popFirst() else {
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
        let config = Configuration()
        config.ipAddress = ipAddress
        config.write()
    }
}

let args = Process.arguments
let commands: [Command] = [
        ConfigCommand(args),
        SetBridgeIpAddressCommand(args)
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

command.execute()
