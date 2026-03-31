using System;
using System.Windows.Media;
using ICSharpCode.AvalonEdit.CodeCompletion;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Editing;
using DbExplorer.Services;

namespace DbExplorer.Controls;

/// <summary>
/// Implements AvalonEdit completion data for SQL intellisense
/// </summary>
public class SqlCompletionData : ICompletionData
{
    public SqlCompletionData(IntellisenseSuggestion suggestion)
    {
        Text = suggestion.Text;
        Description = suggestion.Description;
        Priority = suggestion.Priority;
        Type = suggestion.Type;
        
        // Set image based on type
        Image = GetImageForType(suggestion.Type);
    }
    
    public string Text { get; }
    public object Content => Text;
    public object Description { get; }
    public ImageSource? Image { get; }
    public double Priority { get; }
    public IntellisenseType Type { get; }
    
    public void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        // Replace the typed text with the completion
        textArea.Document.Replace(completionSegment, Text);
    }
    
    private static ImageSource? GetImageForType(IntellisenseType type)
    {
        // Could load actual icons from resources
        // For now, return null (AvalonEdit will show text-only completion)
        return null;
    }
}

