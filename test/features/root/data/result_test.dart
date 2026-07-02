import 'package:flutter_test/flutter_test.dart';
import 'package:sample/features/root/data/result.dart';

void main() {
  test('success result exposes data', () {
    const result = Result.success('ok');

    expect(result.isSuccess, isTrue);
    expect(result.isFailure, isFalse);
    expect(result.getDataOrThrow(), 'ok');
  });

  test('failure result exposes error and stack trace', () {
    final stackTrace = StackTrace.current;
    final result = Result<String>.failure(
      StateError('boom'),
      stackTrace,
    );

    expect(result.isSuccess, isFalse);
    expect(result.isFailure, isTrue);
    expect(result.getErrorOrThrow(), isA<StateError>());
    expect(result.stackTrace, same(stackTrace));
  });

  test('fold branches on success or failure', () {
    const success = Result.success(3);
    final failure = Result<int>.failure(Exception('bad'));

    expect(
      success.fold(
        onSuccess: (data) => data * 2,
        onFailure: (_, _) => -1,
      ),
      6,
    );
    expect(
      failure.fold(
        onSuccess: (data) => data * 2,
        onFailure: (_, _) => -1,
      ),
      -1,
    );
  });
}
