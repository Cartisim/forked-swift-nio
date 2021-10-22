//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// `NIODatagramUDPBootstrapProtocol` is implemented by various underlying transport mechanisms. Typically,
/// this will be the BSD Sockets API implemented by `ClientBootstrap`.
public protocol NIODatagramUDPBootstrapProtocol {
    /// Initialize the connected `SocketChannel` with `initializer`. The most common task in initializer is to add
    /// `ChannelHandler`s to the `ChannelPipeline`.
    ///
    /// The connected `Channel` will operate on `ByteBuffer` as inbound and `IOData` as outbound messages.
    ///
    /// - warning: The `handler` closure may be invoked _multiple times_ so it's usually the right choice to instantiate
    ///            `ChannelHandler`s within `handler`. The reason `handler` may be invoked multiple times is that to
    ///            successfully set up a connection multiple connections might be setup in the process. Assuming a
    ///            hostname that resolves to both IPv4 and IPv6 addresses, NIO will follow
    ///            [_Happy Eyeballs_](https://en.wikipedia.org/wiki/Happy_Eyeballs) and race both an IPv4 and an IPv6
    ///            connection. It is possible that both connections get fully established before the IPv4 connection
    ///            will be closed again because the IPv6 connection 'won the race'. Therefore the `channelInitializer`
    ///            might be called multiple times and it's important not to share stateful `ChannelHandler`s in more
    ///            than one `Channel`.
    ///
    /// - parameters:
    ///     - handler: A closure that initializes the provided `Channel`.
    func channelInitializer(_ handler: @escaping (Channel) -> EventLoopFuture<Void>) -> Self
    
    /// Per bootstrap, you can only set the `protocolHandlers` once. Typically, `protocolHandlers` are used for the TLS
    /// implementation. Most notably, `NIOClientTCPBootstrap`, NIO's "universal bootstrap" abstraction, uses
    /// `protocolHandlers` to add the required `ChannelHandler`s for many TLS implementations.
    func protocolHandlers(_ handlers: @escaping () -> [ChannelHandler]) -> Self

    /// Specifies a `ChannelOption` to be applied to the `SocketChannel`.
    ///
    /// - parameters:
    ///     - option: The option to be applied.
    ///     - value: The value for the option.
    func channelOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> Self
    
//    /// Apply any understood convenience options to the bootstrap, removing them from the set of options if they are consumed.
//    /// Method is optional to implement and should never be directly called by users.
//    /// - parameters:
//    ///     - options:  The options to try applying - the options applied should be consumed from here.
//    /// - returns: The updated bootstrap with and options applied.
//    func _applyChannelConvenienceOptions(_ options: inout ChannelOptions.TCPConvenienceOptions) -> Self

    /// - parameters:
    ///     - timeout: The timeout that will apply to the connection attempt.
    func connectTimeout(_ timeout: TimeAmount) -> Self
    
    
    /// Specify the `host` and `port` to connect to for the TCP `Channel` that will be established.
    ///
    /// - parameters:
    ///     - host: The host to connect to.
    ///     - port: The port to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    func bind(host: String, port: Int) -> EventLoopFuture<Channel>

    /// Specify the `address` to connect to for the TCP `Channel` that will be established.
    ///
    /// - parameters:
    ///     - address: The address to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    func bind(to address: SocketAddress) -> EventLoopFuture<Channel>

    /// Specify the `unixDomainSocket` path to connect to for the UDS `Channel` that will be established.
    ///
    /// - parameters:
    ///     - unixDomainSocketPath: The _Unix domain socket_ path to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    func bind(unixDomainSocketPath: String) -> EventLoopFuture<Channel>
}

/// `NIODatagramUDPBootstrap` is a bootstrap that allows you to bootstrap client TCP connections using NIO on BSD Sockets,
/// NIO Transport Services, or other ways.
///
/// Usually, to bootstrap a connection with SwiftNIO, you have to match the right `EventLoopGroup`, the right bootstrap,
/// and the right TLS implementation. Typical choices involve:
///  - `MultiThreadedEventLoopGroup`, `ClientBootstrap`, and `NIOSSLClientHandler` (from
///    [`swift-nio-ssl`](https://github.com/apple/swift-nio-ssl)) for NIO on BSD sockets.
///  - `NIOTSEventLoopGroup`, `NIOTSConnectionBootstrap`, and the Network.framework TLS implementation (all from
///    [`swift-nio-transport-services`](https://github.com/apple/swift-nio-transport-services).


public struct NIODatagramUDPBootstrap {
    public let underlyingBootstrap: NIODatagramUDPBootstrapProtocol
    private let tlsEnablerTypeErased: (NIODatagramUDPBootstrapProtocol) -> NIODatagramUDPBootstrapProtocol

    /// Initialize a `NIODatagramUDPBootstrap` using the underlying `Bootstrap` alongside a compatible `TLS`
    /// implementation.
    ///
    /// - note: If you do not require `TLS`, you can use `NIOInsecureNoTLS` which supports only plain-text
    ///         connections. We highly recommend to always use TLS.
    ///
    /// - parameters:
    ///     - bootstrap: The underlying bootstrap to use.
    ///     - tls: The TLS implementation to use, needs to be compatible with `Bootstrap`.
    public init<Bootstrap: NIODatagramUDPBootstrapProtocol,
                TLS: NIODatagramTLSProvider>(_ bootstrap: Bootstrap, tls: TLS) where TLS.Bootstrap == Bootstrap {
        self.underlyingBootstrap = bootstrap
        self.tlsEnablerTypeErased = { bootstrap in
            return tls.enableTLS(bootstrap as! TLS.Bootstrap)
        }
    }

    private init(_ bootstrap: NIODatagramUDPBootstrapProtocol,
                 tlsEnabler: @escaping (NIODatagramUDPBootstrapProtocol) -> NIODatagramUDPBootstrapProtocol) {
        self.underlyingBootstrap = bootstrap
        self.tlsEnablerTypeErased = tlsEnabler
    }
    
    internal init(_ original : NIODatagramUDPBootstrap, updating underlying : NIODatagramUDPBootstrapProtocol) {
        self.underlyingBootstrap = underlying
        self.tlsEnablerTypeErased = original.tlsEnablerTypeErased
    }

    /// Initialize the connected `SocketChannel` with `initializer`. The most common task in initializer is to add
    /// `ChannelHandler`s to the `ChannelPipeline`.
    ///
    /// The connected `Channel` will operate on `ByteBuffer` as inbound and `IOData` as outbound messages.
    ///
    /// - warning: The `handler` closure may be invoked _multiple times_ so it's usually the right choice to instantiate
    ///            `ChannelHandler`s within `handler`. The reason `handler` may be invoked multiple times is that to
    ///            successfully set up a connection multiple connections might be setup in the process. Assuming a
    ///            hostname that resolves to both IPv4 and IPv6 addresses, NIO will follow
    ///            [_Happy Eyeballs_](https://en.wikipedia.org/wiki/Happy_Eyeballs) and race both an IPv4 and an IPv6
    ///            connection. It is possible that both connections get fully established before the IPv4 connection
    ///            will be closed again because the IPv6 connection 'won the race'. Therefore the `channelInitializer`
    ///            might be called multiple times and it's important not to share stateful `ChannelHandler`s in more
    ///            than one `Channel`.
    ///
    /// - parameters:
    ///     - handler: A closure that initializes the provided `Channel`.
    public func channelInitializer(_ handler: @escaping (Channel) -> EventLoopFuture<Void>) -> NIODatagramUDPBootstrap {
        return NIODatagramUDPBootstrap(self.underlyingBootstrap.channelInitializer(handler),
                                     tlsEnabler: self.tlsEnablerTypeErased)
    }

    /// Specifies a `ChannelOption` to be applied to the `SocketChannel`.
    ///
    /// - parameters:
    ///     - option: The option to be applied.
    ///     - value: The value for the option.
    public func channelOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> NIODatagramUDPBootstrap {
        return NIODatagramUDPBootstrap(self.underlyingBootstrap.channelOption(option, value: value),
                                     tlsEnabler: self.tlsEnablerTypeErased)
    }

    /// - parameters:
    ///     - timeout: The timeout that will apply to the connection attempt.
    public func connectTimeout(_ timeout: TimeAmount) -> NIODatagramUDPBootstrap {
        return NIODatagramUDPBootstrap(self.underlyingBootstrap.connectTimeout(timeout),
                                     tlsEnabler: self.tlsEnablerTypeErased)
    }
    
    
    /// Specify the `host` and `port` to connect to for the TCP `Channel` that will be established.
    ///
    /// - parameters:
    ///     - host: The host to connect to.
    ///     - port: The port to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    public func connect(host: String, port: Int) -> EventLoopFuture<Channel> {
        return self.underlyingBootstrap.bind(host: host, port: port)
    }

    /// Specify the `address` to connect to for the TCP `Channel` that will be established.
    ///
    /// - parameters:
    ///     - address: The address to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    public func connect(to address: SocketAddress) -> EventLoopFuture<Channel> {
        return self.underlyingBootstrap.bind(to: address)
    }

    /// Specify the `unixDomainSocket` path to connect to for the UDS `Channel` that will be established.
    ///
    /// - parameters:
    ///     - unixDomainSocketPath: The _Unix domain socket_ path to connect to.
    /// - returns: An `EventLoopFuture<Channel>` to deliver the `Channel` when connected.
    public func connect(unixDomainSocketPath: String) -> EventLoopFuture<Channel> {
        return self.underlyingBootstrap.bind(unixDomainSocketPath: unixDomainSocketPath)
    }


    @discardableResult
    public func enableTLS() -> NIODatagramUDPBootstrap {
        return NIODatagramUDPBootstrap(self.tlsEnablerTypeErased(self.underlyingBootstrap),
                                     tlsEnabler: self.tlsEnablerTypeErased)
    }
}

public protocol NIODatagramTLSProvider {
    associatedtype Bootstrap

    func enableTLS(_ bootstrap: Bootstrap) -> Bootstrap
}

public struct NIODatagramInsecureNoTLS<Bootstrap: NIODatagramUDPBootstrapProtocol>: NIODatagramTLSProvider {
    public init() {}

    public func enableTLS(_ bootstrap: Bootstrap) -> Bootstrap {
        fatalError("NIOInsecureNoTLS cannot enable TLS.")
    }
}
