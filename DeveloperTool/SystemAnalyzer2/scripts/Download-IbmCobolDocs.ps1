#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Stages IBM COBOL / VSAM documentation PDFs for RAG ingestion (see SystemAnalyzer2 plan).

.NOTES
  Run from any directory. Adjust $StagingRoot if needed.
  Next steps: convert with Pdf2Markdown / AiDoc, then build_index.py per RAG name.
#>
$ErrorActionPreference = 'Stop'
if (Get-Module -ListAvailable -Name GlobalFunctions) {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
}
function Write-StagingLog([string]$Message) {
    if (Get-Command Write-LogMessage -ErrorAction SilentlyContinue) {
        Write-LogMessage $Message -Level INFO
    } else {
        Write-Host $Message
    }
}
$StagingRoot = 'C:\opt\data\AiDoc.Library.staging'

$targets = @(
    @{ Name = 'ibm-enterprise-cobol-zos-docs'; ZipUrl = 'https://www.ibm.com/docs/en/SS6SG3_6.5/download/cobolv6r5_en.zip' },
    @{ Name = 'ibm-enterprise-cobol-zos-docs-6.4'; ZipUrl = 'https://www.ibm.com/docs/en/SS6SG3_6.4.0/download/cobolv6r4_en.zip' },
    @{ Name = 'ibm-cobol-aix-docs'; Pdfs = @(
            'https://publibfp.boulder.ibm.com/epubs/pdf/c2754040.pdf',
            'https://publibfp.boulder.ibm.com/epubs/pdf/c2754030.pdf',
            'https://publib.boulder.ibm.com/epubs/pdf/c2754020.pdf',
            'https://publib.boulder.ibm.com/epubs/pdf/cob4vs00.pdf'
        ) },
    @{ Name = 'ibm-cobol-linux-x86-docs'; Pdfs = @(
            'https://www.ibm.com/docs/en/SS7FZ2_1.2.0/pdf/pglin.pdf',
            'https://www.ibm.com/docs/en/SS7FZ2_1.2.0/pdf/lrlin.pdf',
            'https://www.ibm.com/docs/en/SS7FZ2_1.2.0/pdf/iglin.pdf',
            'https://www.ibm.com/docs/en/SS7FZ2_1.2.0/pdf/migration.pdf',
            'https://www.ibm.com/docs/en/SS7FZ2_1.2.0/pdf/whatsnew.pdf'
        ) },
    @{ Name = 'ibm-zos-vsam-docs'; Pdfs = @(
            'https://www.ibm.com/docs/en/SSLTBW_2.4.0/pdf/idai200_v2r4.pdf',
            'https://www.ibm.com/docs/en/SSLTBW_2.2.0/pdf/dgt3d410.pdf',
            'https://www.ibm.com/docs/SSLTBW_3.2.0/pdf/idak100_v3r2.pdf'
        ) }
)

foreach ($t in $targets) {
    $dest = Join-Path $StagingRoot $t.Name
    $pdfDir = Join-Path $dest 'pdf'
    New-Item -ItemType Directory -Path $pdfDir -Force | Out-Null
    Write-StagingLog "[$($t.Name)] -> $($pdfDir)"

    if ($t.ZipUrl) {
        $zipFile = Join-Path $dest 'bundle.zip'
        Invoke-WebRequest -Uri $t.ZipUrl -OutFile $zipFile -UseBasicParsing
        Expand-Archive -Path $zipFile -DestinationPath $pdfDir -Force
    }

    if ($t.Pdfs) {
        foreach ($u in $t.Pdfs) {
            $leaf = [Uri]$u | ForEach-Object { $_.Segments[-1] }
            $out = Join-Path $pdfDir $leaf
            Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing
        }
    }
}

Write-StagingLog "Done. Staging root: $($StagingRoot)"
