using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DbExplorer.Models;

/// <summary>
/// Represents a table in the selection dialog with FK relationship information.
/// </summary>
public class TableSelectionItem : INotifyPropertyChanged
{
    private bool _isSelected;
    
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string FullName => $"{Schema}.{TableName}";
    
    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected != value)
            {
                _isSelected = value;
                OnPropertyChanged();
            }
        }
    }
    
    public int OutgoingFKCount { get; set; }
    public int IncomingFKCount { get; set; }
    public List<ForeignKeyInfo> OutgoingFKs { get; set; } = new();
    public List<ForeignKeyInfo> IncomingFKs { get; set; } = new();
    
    public event PropertyChangedEventHandler? PropertyChanged;
    
    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
    
    public override bool Equals(object? obj)
    {
        if (obj is TableSelectionItem other)
        {
            return Schema == other.Schema && TableName == other.TableName;
        }
        return false;
    }
    
    public override int GetHashCode()
    {
        return HashCode.Combine(Schema, TableName);
    }
}
