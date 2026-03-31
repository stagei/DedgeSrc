using GenericLogHandler.Core.Models.Configuration;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;

namespace GenericLogHandler.ImportService.Services;

/// <summary>
/// Provides retry logic with exponential backoff and circuit breaker pattern
/// </summary>
public class RetryService
{
    private readonly ILogger<RetryService> _logger;
    private readonly RetryPolicySettings _settings;
    private readonly ConcurrentDictionary<string, CircuitState> _circuitStates = new();
    private readonly Random _random = new();

    public RetryService(ILogger<RetryService> logger, RetryPolicySettings settings)
    {
        _logger = logger;
        _settings = settings;
    }

    /// <summary>
    /// Execute an action with retry logic
    /// </summary>
    public async Task<T> ExecuteAsync<T>(
        string operationName,
        string sourceKey,
        Func<Task<T>> operation,
        CancellationToken cancellationToken = default)
    {
        // Check circuit breaker
        if (_settings.EnableCircuitBreaker && IsCircuitOpen(sourceKey))
        {
            _logger.LogWarning("Circuit breaker is open for source {Source}. Skipping operation {Operation}",
                sourceKey, operationName);
            throw new CircuitBreakerOpenException(sourceKey);
        }

        Exception? lastException = null;
        int attempt = 0;

        while (attempt <= _settings.MaxRetries)
        {
            try
            {
                if (attempt > 0)
                {
                    _logger.LogInformation("Retry attempt {Attempt}/{MaxRetries} for {Operation} on {Source}",
                        attempt, _settings.MaxRetries, operationName, sourceKey);
                }

                var result = await operation();
                
                // Success - reset circuit breaker
                ResetCircuit(sourceKey);
                return result;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                lastException = ex;
                attempt++;

                if (attempt > _settings.MaxRetries)
                {
                    _logger.LogError(ex, "All {MaxRetries} retry attempts failed for {Operation} on {Source}",
                        _settings.MaxRetries, operationName, sourceKey);
                    
                    // Record failure for circuit breaker
                    RecordFailure(sourceKey);
                    throw;
                }

                var delay = CalculateDelay(attempt);
                _logger.LogWarning(ex, "Attempt {Attempt} failed for {Operation} on {Source}. Retrying in {Delay}ms",
                    attempt, operationName, sourceKey, delay);

                await Task.Delay(delay, cancellationToken);
            }
        }

        throw lastException ?? new InvalidOperationException("Unexpected retry loop exit");
    }

    /// <summary>
    /// Execute an action with retry logic (no return value)
    /// </summary>
    public async Task ExecuteAsync(
        string operationName,
        string sourceKey,
        Func<Task> operation,
        CancellationToken cancellationToken = default)
    {
        await ExecuteAsync(operationName, sourceKey, async () =>
        {
            await operation();
            return true;
        }, cancellationToken);
    }

    /// <summary>
    /// Calculate delay with exponential backoff and jitter
    /// </summary>
    private int CalculateDelay(int attempt)
    {
        // Exponential backoff: initialDelay * (multiplier ^ (attempt - 1))
        var exponentialDelay = _settings.InitialDelayMs * Math.Pow(_settings.BackoffMultiplier, attempt - 1);
        
        // Cap at max delay
        var cappedDelay = Math.Min(exponentialDelay, _settings.MaxDelayMs);
        
        // Add jitter
        if (_settings.JitterFactor > 0)
        {
            var jitterRange = cappedDelay * _settings.JitterFactor;
            var jitter = (_random.NextDouble() * 2 - 1) * jitterRange; // -jitterRange to +jitterRange
            cappedDelay += jitter;
        }

        return (int)Math.Max(0, cappedDelay);
    }

    /// <summary>
    /// Check if circuit breaker is open for a source
    /// </summary>
    private bool IsCircuitOpen(string sourceKey)
    {
        if (!_circuitStates.TryGetValue(sourceKey, out var state))
            return false;

        if (state.State != CircuitBreakerState.Open)
            return false;

        // Check if reset time has passed
        if (DateTime.UtcNow > state.ResetTime)
        {
            state.State = CircuitBreakerState.HalfOpen;
            _logger.LogInformation("Circuit breaker for {Source} is now half-open. Next operation will test recovery.",
                sourceKey);
            return false;
        }

        return true;
    }

    /// <summary>
    /// Record a failure for circuit breaker tracking
    /// </summary>
    private void RecordFailure(string sourceKey)
    {
        var state = _circuitStates.GetOrAdd(sourceKey, _ => new CircuitState());
        
        lock (state)
        {
            state.ConsecutiveFailures++;
            state.LastFailure = DateTime.UtcNow;

            if (state.ConsecutiveFailures >= _settings.CircuitBreakerThreshold)
            {
                state.State = CircuitBreakerState.Open;
                state.ResetTime = DateTime.UtcNow.AddSeconds(_settings.CircuitBreakerResetSeconds);
                
                _logger.LogWarning(
                    "Circuit breaker OPENED for {Source} after {Failures} consecutive failures. Will retry after {ResetTime}",
                    sourceKey, state.ConsecutiveFailures, state.ResetTime);
            }
        }
    }

    /// <summary>
    /// Reset circuit breaker after successful operation
    /// </summary>
    private void ResetCircuit(string sourceKey)
    {
        if (_circuitStates.TryGetValue(sourceKey, out var state))
        {
            lock (state)
            {
                if (state.State != CircuitBreakerState.Closed)
                {
                    _logger.LogInformation("Circuit breaker CLOSED for {Source} after successful operation", sourceKey);
                }
                state.State = CircuitBreakerState.Closed;
                state.ConsecutiveFailures = 0;
            }
        }
    }

    /// <summary>
    /// Get circuit breaker status for all sources
    /// </summary>
    public Dictionary<string, (CircuitBreakerState State, int Failures, DateTime? ResetTime)> GetCircuitStatus()
    {
        return _circuitStates.ToDictionary(
            kvp => kvp.Key,
            kvp => (kvp.Value.State, kvp.Value.ConsecutiveFailures, 
                    kvp.Value.State == CircuitBreakerState.Open ? kvp.Value.ResetTime : (DateTime?)null));
    }

    /// <summary>
    /// Manually reset circuit breaker for a source
    /// </summary>
    public void ManualReset(string sourceKey)
    {
        if (_circuitStates.TryGetValue(sourceKey, out var state))
        {
            lock (state)
            {
                state.State = CircuitBreakerState.Closed;
                state.ConsecutiveFailures = 0;
                _logger.LogInformation("Circuit breaker manually reset for {Source}", sourceKey);
            }
        }
    }

    private class CircuitState
    {
        public CircuitBreakerState State { get; set; } = CircuitBreakerState.Closed;
        public int ConsecutiveFailures { get; set; }
        public DateTime LastFailure { get; set; }
        public DateTime ResetTime { get; set; }
    }
}

public enum CircuitBreakerState
{
    Closed,
    Open,
    HalfOpen
}

public class CircuitBreakerOpenException : Exception
{
    public string SourceKey { get; }

    public CircuitBreakerOpenException(string sourceKey)
        : base($"Circuit breaker is open for source: {sourceKey}")
    {
        SourceKey = sourceKey;
    }
}
