using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using AutoDocNew.Core;

namespace AutoDocNew.Parsers;

/// <summary>
/// Thread-safe Mermaid diagram writer.
/// Encapsulates MMD output state per parse call.
/// Converted line-by-line from Write-AutodocMermaidLine (lines 690-789 in AutoDocFunctions.psm1)
/// </summary>
public class MermaidWriter
{
    private readonly bool _useClientSideRender;
    private readonly string? _mmdFilename;
    private readonly List<string> _mmdFlowContent;
    private readonly HashSet<string> _duplicateLineCheck;
    private int _sequenceNumber;

    /// <summary>
    /// Creates a new MermaidWriter.
    /// Line 690-730: Constructor mirrors script-level variable initialization
    /// </summary>
    public MermaidWriter(bool clientSideRender, string? mmdFilename, string header)
    {
        _useClientSideRender = clientSideRender;
        _mmdFilename = mmdFilename;
        _mmdFlowContent = new List<string>();
        _duplicateLineCheck = new HashSet<string>(StringComparer.Ordinal);
        _sequenceNumber = 0;

        if (clientSideRender)
        {
            _mmdFlowContent.Add(header);
        }
        else if (mmdFilename != null)
        {
            File.WriteAllText(mmdFilename, header + Environment.NewLine, Encoding.UTF8);
        }
    }

    /// <summary>
    /// Write a line to the Mermaid diagram.
    /// Converted line-by-line from Write-AutodocMermaidLine (lines 764-788)
    /// Line 764: if (-not $script:duplicateLineCheckSet.Contains($MmdString))
    /// Line 766-773: Add sequence numbers to arrows
    /// Line 776-784: Write to appropriate output
    /// Line 787: [void]$script:duplicateLineCheckSet.Add($MmdString)
    /// </summary>
    public void WriteLine(string mmdString)
    {
        // Line 732-748: Null/empty check
        if (string.IsNullOrWhiteSpace(mmdString))
            return;

        // Line 764: Duplicate check
        if (_duplicateLineCheck.Contains(mmdString))
            return;

        // Line 766-773: Add sequence numbers to arrows
        if (mmdString.Contains("-->") && !mmdString.ToLower().Contains("initiated-->"))
        {
            int pos1 = mmdString.IndexOf("-->");
            int pos2 = mmdString.LastIndexOf("-->");
            if (pos1 == pos2)
            {
                // Line 770-771: $script:sequenceNumber++; insert (#N)
                _sequenceNumber++;
                mmdString = mmdString.Substring(0, pos1) + $"(#{_sequenceNumber})" + mmdString.Substring(pos1);
            }
        }

        // Line 776-784: Write to appropriate output
        if (_useClientSideRender)
        {
            // Line 777: [void]$script:mmdFlowContent.Add($MmdString)
            _mmdFlowContent.Add(mmdString);
        }
        else if (_mmdFilename != null)
        {
            // Line 784: Add-Content -Path $script:mmdFilename -Value $MmdString -Force
            File.AppendAllText(_mmdFilename, mmdString + Environment.NewLine, Encoding.UTF8);
        }

        // Line 787: [void]$script:duplicateLineCheckSet.Add($MmdString)
        _duplicateLineCheck.Add(mmdString);
    }

    /// <summary>
    /// Get all content as a single string (for embedding in HTML template).
    /// </summary>
    public string GetContent() => string.Join("\n", _mmdFlowContent);

    /// <summary>
    /// Get all content lines.
    /// </summary>
    public List<string> GetContentList() => _mmdFlowContent;

    /// <summary>
    /// Get the MMD filename.
    /// </summary>
    public string? MmdFilename => _mmdFilename;

    /// <summary>
    /// Whether using client-side rendering.
    /// </summary>
    public bool UseClientSideRender => _useClientSideRender;

    /// <summary>
    /// Get the current sequence number.
    /// </summary>
    public int SequenceNumber => _sequenceNumber;
}
