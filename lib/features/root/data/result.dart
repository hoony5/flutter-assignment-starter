class Result<T> {
  const Result.success(this.data)
    : error = null,
      stackTrace = null,
      _isSuccess = true;

  const Result.failure(this.error, [this.stackTrace])
    : data = null,
      _isSuccess = false;

  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final bool _isSuccess;

  bool get isSuccess => _isSuccess;
  bool get isFailure => !_isSuccess;

  T dataOrThrow() {
    if (isFailure) {
      throw StateError('Cannot read data from a failed Result.');
    }
    return data as T;
  }

  Object errorOrThrow() {
    if (isSuccess) {
      throw StateError('Cannot read error from a successful Result.');
    }
    return error as Object;
  }

  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(Object error, StackTrace? stackTrace) onFailure,
  }) {
    if (isSuccess) {
      return onSuccess(dataOrThrow());
    }
    return onFailure(errorOrThrow(), stackTrace);
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'Result.success($data)';
    }
    return 'Result.failure($error)';
  }
}
