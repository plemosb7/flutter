// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:conductor_core/conductor_core.dart';
import 'package:conductor_core/packages_autoroller.dart';
import 'package:file/memory.dart';
import 'package:platform/platform.dart';

import './common.dart';

void main() {
  const String flutterRoot = '/flutter';
  const String checkoutsParentDirectory = '$flutterRoot/dev/conductor';
  const String githubClient = 'gh';
  const String token = '0123456789abcdef';
  const String orgName = 'flutter-roller';
  const String mirrorUrl = 'https://githost.com/flutter-roller/flutter.git';
  final String localPathSeparator = const LocalPlatform().pathSeparator;
  final String localOperatingSystem = const LocalPlatform().operatingSystem;
  late MemoryFileSystem fileSystem;
  late TestStdio stdio;
  late FrameworkRepository framework;
  late PackageAutoroller autoroller;
  late FakeProcessManager processManager;

  setUp(() {
    stdio = TestStdio();
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.empty();
    final FakePlatform platform = FakePlatform(
      environment: <String, String>{
        'HOME': <String>['path', 'to', 'home'].join(localPathSeparator),
      },
      operatingSystem: localOperatingSystem,
      pathSeparator: localPathSeparator,
    );
    final Checkouts checkouts = Checkouts(
      fileSystem: fileSystem,
      parentDirectory: fileSystem.directory(checkoutsParentDirectory)
        ..createSync(recursive: true),
      platform: platform,
      processManager: processManager,
      stdio: stdio,
    );
    framework = FrameworkRepository(
      checkouts,
      mirrorRemote: const Remote(
        name: RemoteName.mirror,
        url: mirrorUrl,
      ),
    );

    autoroller = PackageAutoroller(
      githubClient: githubClient,
      token: token,
      framework: framework,
      orgName: orgName,
      processManager: processManager,
    );
  });

  test('can roll with correct inputs', () async {
    final StreamController<List<int>> controller =
        StreamController<List<int>>();
    processManager.addCommands(<FakeCommand>[
      FakeCommand(command: const <String>[
        'gh',
        'auth',
        'login',
        '--hostname',
        'github.com',
        '--git-protocol',
        'https',
        '--with-token',
      ], stdin: io.IOSink(controller.sink)),
      const FakeCommand(command: <String>[
        'git',
        'clone',
        '--origin',
        'upstream',
        '--',
        FrameworkRepository.defaultUpstream,
        '$checkoutsParentDirectory/flutter_conductor_checkouts/framework',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'remote',
        'add',
        'mirror',
        mirrorUrl,
      ]),
      const FakeCommand(command: <String>[
        'git',
        'fetch',
        'mirror',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'checkout',
        FrameworkRepository.defaultBranch,
      ]),
      const FakeCommand(command: <String>[
        'git',
        'rev-parse',
        'HEAD',
      ], stdout: 'deadbeef'),
      const FakeCommand(command: <String>[
        'git',
        'ls-remote',
        '--heads',
        'mirror',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'checkout',
        '-b',
        'packages-autoroller-branch-1',
      ]),
      const FakeCommand(command: <String>[
        '$checkoutsParentDirectory/flutter_conductor_checkouts/framework/bin/flutter',
        'help',
      ]),
      const FakeCommand(command: <String>[
        '$checkoutsParentDirectory/flutter_conductor_checkouts/framework/bin/flutter',
        '--verbose',
        'update-packages',
        '--force-upgrade',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'status',
        '--porcelain',
      ], stdout: '''
 M packages/foo/pubspec.yaml
 M packages/bar/pubspec.yaml
 M dev/integration_tests/test_foo/pubspec.yaml
'''),
      const FakeCommand(command: <String>[
        'git',
        'add',
        '--all',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'commit',
        '--message',
        'roll packages',
        '--author="flutter-packages-autoroller <flutter-packages-autoroller@google.com>"',
      ]),
      const FakeCommand(command: <String>[
        'git',
        'rev-parse',
        'HEAD',
      ], stdout: '000deadbeef'),
      const FakeCommand(command: <String>[
        'git',
        'push',
        mirrorUrl,
        'packages-autoroller-branch-1:packages-autoroller-branch-1',
      ]),
      const FakeCommand(command: <String>[
        'gh',
        'pr',
        'create',
        '--title',
        'Roll pub packages',
        '--body',
        'This PR was generated by `flutter update-packages --force-upgrade`.',
        '--head',
        'flutter-roller:packages-autoroller-branch-1',
        '--base',
        FrameworkRepository.defaultBranch,
      ]),
      const FakeCommand(command: <String>[
        'gh',
        'auth',
        'logout',
        '--hostname',
        'github.com',
      ]),
    ]);
    final Future<void> rollFuture = autoroller.roll();
    final String givenToken =
        await controller.stream.transform(const Utf8Decoder()).join();
    expect(givenToken, token);
    await rollFuture;
  });
}
