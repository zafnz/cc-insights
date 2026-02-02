/// Core library containing ClaudeBackend and ClaudeSession.
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'backend_interface.dart';
import 'protocol.dart';
import 'types/callbacks.dart';
import 'types/content_blocks.dart';
import 'types/errors.dart';
import 'types/sdk_messages.dart';
import 'types/session_options.dart';
import 'types/usage.dart';

part 'backend.dart';
part 'session.dart';
