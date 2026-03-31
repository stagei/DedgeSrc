namespace SqlMmdConverter.Exceptions;

/// <summary>
/// Exception thrown when Mermaid ERD parsing fails.
/// </summary>
public class MmdParseException : Exception
{
    /// <summary>
    /// Initializes a new instance of the <see cref="MmdParseException"/> class.
    /// </summary>
    public MmdParseException()
    {
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="MmdParseException"/> class with a specified error message.
    /// </summary>
    /// <param name="message">The message that describes the error.</param>
    public MmdParseException(string message)
        : base(message)
    {
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="MmdParseException"/> class with a specified error message
    /// and a reference to the inner exception that is the cause of this exception.
    /// </summary>
    /// <param name="message">The error message that explains the reason for the exception.</param>
    /// <param name="innerException">The exception that is the cause of the current exception.</param>
    public MmdParseException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

