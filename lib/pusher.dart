import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pusher.g.dart';

enum PusherConnectionState {
  connecting,
  connected,
  disconnecting,
  disconnected,
  reconnecting,
  reconnectingWhenNetworkBecomesReachable
}

/// Used to listen to events sent through pusher
class Pusher {
  Pusher._();

  static const _channel =
      const MethodChannel('plugins.indoor.solutions/pusher');
  static const _eventChannel =
      const EventChannel('plugins.indoor.solutions/pusherStream');

  static void Function(ConnectionStateChange?)? _onConnectionStateChange;
  static void Function(ConnectionError?)? _onError;

  static Map<String, void Function(Event?)?> eventCallbacks =
      Map<String, void Function(Event?)?>();

  /// Setup app key and options
  static Future init(
    String appKey,
    PusherOptions options, {
    bool enableLogging = false,
  }) async {
    assert(appKey != null);
    assert(options != null);

    _eventChannel.receiveBroadcastStream().listen(_handleEvent);

    final initArgs = jsonEncode(InitArgs(
      appKey,
      options,
      isLoggingEnabled: enableLogging,
    ).toJson());

    await _channel.invokeMethod('init', initArgs);
  }

  /// Connect the client to pusher
  static Future connect({
    void Function(ConnectionStateChange?)? onConnectionStateChange,
    void Function(ConnectionError?)? onError,
  }) async {
    _onConnectionStateChange = onConnectionStateChange;
    _onError = onError;
    await _channel.invokeMethod('connect');
  }

  /// Disconnect the client from pusher
  static Future disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Subscribe to a channel
  /// Use the returned [Channel] to bind events
  static Future<Channel> subscribe(String channelName) async {
    await _channel.invokeMethod('subscribe', channelName);
    return Channel(name: channelName);
  }

  /// Subscribe to a channel
  /// Use the returned [Channel] to bind events
  static Future<String?> getUsers(String channelName) async {
    String? result = await _channel.invokeMethod('getUsers', channelName);
    return result;
  }

  /// Unsubscribe from a channel
  static Future unsubscribe(String channelName) async {
    await _channel.invokeMethod('unsubscribe', channelName);
  }

  static Future _trigger(
      String? channelName, String eventName, String data) async {
    final bindArgs = jsonEncode(BindArgs(
      channelName: channelName,
      eventName: eventName,
      data: data,
    ).toJson());

    await _channel.invokeMethod('trigger', bindArgs);
  }

  static Future _bind(
    String channelName,
    String eventName, {
    void Function(Event?)? onEvent,
  }) async {
    final bindArgs = jsonEncode(BindArgs(
      channelName: channelName,
      eventName: eventName,
    ).toJson());

    eventCallbacks[channelName + eventName] = onEvent;
    await _channel.invokeMethod('bind', bindArgs);
  }

  static Future _unbind(String channelName, String eventName) async {
    final bindArgs = jsonEncode(BindArgs(
      channelName: channelName,
      eventName: eventName,
    ).toJson());

    eventCallbacks.remove(channelName + eventName);
    await _channel.invokeMethod('unbind', bindArgs);
  }

  static void _handleEvent([dynamic arguments]) {
    var message = PusherEventStreamMessage.fromJson(jsonDecode(arguments));

    if (message.isEvent) {
      var callback =
          eventCallbacks[message.event!.channel! + message.event!.event!];
      if (callback != null) {
        callback(message.event);
      }
    } else if (message.isConnectionStateChange) {
      if (_onConnectionStateChange != null) {
        _onConnectionStateChange!(message.connectionStateChange);
      }
    } else if (message.isConnectionError) {
      if (_onError != null) {
        _onError!(message.connectionError);
      }
    }
  }
}

@JsonSerializable()
class InitArgs {
  final String? appKey;
  final PusherOptions? options;
  final bool? isLoggingEnabled;

  InitArgs(this.appKey, this.options, {this.isLoggingEnabled = false});

  factory InitArgs.fromJson(Map<String, dynamic> json) =>
      _$InitArgsFromJson(json);

  Map<String, dynamic> toJson() => _$InitArgsToJson(this);
}

@JsonSerializable()
class BindArgs {
  final String? channelName;
  final String? eventName;
  final String? data;

  BindArgs({this.channelName, this.eventName, this.data});

  factory BindArgs.fromJson(Map<String, dynamic> json) =>
      _$BindArgsFromJson(json);

  Map<String, dynamic> toJson() => _$BindArgsToJson(this);
}

@JsonSerializable(includeIfNull: false)
class PusherOptions {
  final PusherAuth? auth;
  final String? cluster;
  final String? host;
  final int? port;
  final bool? encrypted;
  final int? activityTimeout;

  PusherOptions({
    this.auth,
    this.cluster,
    this.host,
    this.port = 443,
    this.encrypted = true,
    this.activityTimeout = 30000,
  });

  factory PusherOptions.fromJson(Map<String, dynamic> json) =>
      _$PusherOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$PusherOptionsToJson(this);
}

@JsonSerializable()
class PusherAuth {
  final String? endpoint;
  final Map<String, String>? headers;

  PusherAuth(
    this.endpoint, {
    this.headers = const {'Content-Type': 'application/x-www-form-urlencoded'},
  });

  factory PusherAuth.fromJson(Map<String, dynamic> json) =>
      _$PusherAuthFromJson(json);

  Map<String, dynamic> toJson() => _$PusherAuthToJson(this);
}

@JsonSerializable()
class ConnectionStateChange {
  final String? currentState;
  final String? previousState;

  ConnectionStateChange({this.currentState, this.previousState});

  factory ConnectionStateChange.fromJson(Map<String, dynamic> json) =>
      _$ConnectionStateChangeFromJson(json);

  Map<String, dynamic> toJson() => _$ConnectionStateChangeToJson(this);
}

@JsonSerializable()
class ConnectionError {
  final String? message;
  final String? code;
  final String? exception;

  ConnectionError({this.message, this.code, this.exception});

  factory ConnectionError.fromJson(Map<String, dynamic> json) =>
      _$ConnectionErrorFromJson(json);

  Map<String, dynamic> toJson() => _$ConnectionErrorToJson(this);
}

@JsonSerializable()
class Event {
  final String? channel;
  final String? event;
  final String? data;

  Event({this.channel, this.event, this.data});

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);

  Map<String, dynamic> toJson() => _$EventToJson(this);
}

class Channel {
  final String? name;

  Channel({this.name});

  /// Bind to listen for events sent on the given channel
  Future bind(String eventName, void Function(Event?) onEvent) async {
    await Pusher._bind(name!, eventName, onEvent: onEvent);
  }

  Future unbind(String eventName) async {
    await Pusher._unbind(name!, eventName);
  }

  /// Trigger [eventName] (will be prefixed with "client-" in case you have not) for [Channel].
  ///
  /// Client events can only be triggered on private and presence channels because they require authentication
  /// You can only trigger a client event once a subscription has been successfully registered with Channels.
  Future trigger(String eventName, {String? data}) async {
    if (!eventName.startsWith('client-')) {
      eventName = "client-$eventName";
    }

    await Pusher._trigger(name, eventName, data ?? "{}");
  }
}

@JsonSerializable()
class PusherEventStreamMessage {
  final Event? event;
  final ConnectionStateChange? connectionStateChange;
  final ConnectionError? connectionError;

  bool get isEvent => event != null;

  bool get isConnectionStateChange => connectionStateChange != null;

  bool get isConnectionError => connectionError != null;

  PusherEventStreamMessage(
      {this.event, this.connectionStateChange, this.connectionError});

  factory PusherEventStreamMessage.fromJson(Map<String, dynamic> json) =>
      _$PusherEventStreamMessageFromJson(json);

  Map<String, dynamic> toJson() => _$PusherEventStreamMessageToJson(this);
}
