
# send email
# cat email.txt | msmtp --account=default <recipient@somedomain.com>

## Configuration file
import os
if len(config) == 0:
  if os.path.isfile("./config.yaml"):
    configfile: "./config.yaml"
  else:
    sys.exit("Make sure there is a config.yaml file in " + os.getcwd() + " or specify one with the --configfile commandline parameter.")

## Make sure that all expected variables from the config file are in the config dictionary
configvars = ['annotation', 'organism', 'build', 'release', 'txome', 'genome', 'gtf', 'salmonindex', 'salmonk', 'STARindex', 'HISAT2index', 'readlength', 'fldMean', 'fldSD', 'metatxt', 'design', 'contrast', 'genesets', 'ncores', 'FASTQ', 'fqext1', 'fqext2', 'fqsuffix', 'output', 'useCondaR', 'Rbin', 'run_trimming', 'run_STAR', 'run_HISAT2', 'run_DRIMSeq', 'run_camera']
for k in configvars:
	if k not in config:
		config[k] = None

## If any of the file paths is missing, replace it with ""
def sanitizefile(str):
	if str is None:
		str = ''
	return str
	
config['txome'] = sanitizefile(config['txome'])
config['gtf'] = sanitizefile(config['gtf'])
config['genome'] = sanitizefile(config['genome'])
config['STARindex'] = sanitizefile(config['STARindex'])
config['HISAT2index'] = sanitizefile(config['HISAT2index'])
config['salmonindex'] = sanitizefile(config['salmonindex'])
config['metatxt'] = sanitizefile(config['metatxt'])
config['metacsv'] = os.path.splitext(os.path.basename(config['metatxt']))[0]+'.csv'

## Read metadata
if not os.path.isfile(config["metatxt"]):
  sys.exit("Metadata file " + config["metatxt"] + " does not exist.")

import pandas as pd
samples = pd.read_csv(config["metatxt"], sep='\t')

if not set(['names','type']).issubset(samples.columns):
  sys.exit("Make sure 'names' and 'type' are columns in " + config["metatxt"])


## Sanitize provided input and output directories
import re
def getpath(str):
	if str in ['', '.', './']:
		return ''
	if str.startswith('./'):
		regex = re.compile('^\./?')
		str = regex.sub('', str)
	if not str.endswith('/'):
		str += '/'
	return str

proj_dir = os.path.abspath(os.path.normpath(getpath(config["proj_dir"])))
outputdir = os.path.abspath(getpath(config["output"])) + "/"
FASTQdir = getpath(config["FASTQ"])

## Define the conda environment for all rules using R
if config["useCondaR"] == True:
	Renv = "envs/environment_R.yaml"
else:
	Renv = "envs/environment.yaml"

## Define the R binary
Rbin = config["Rbin"]

# The config.yaml files determines which steps should be performed
def stringtie_output(wildcards):
	input = []
	input.extend(expand(outputdir + "stringtie/{sample}/{sample}.gtf", sample = samples.names[samples.type == 'PE'].values.tolist()))
	return input
	
def dbtss_output(wildcards):
	input = []
	input.extend(expand(outputdir + "dbtss_coverage/{sample}_dbtss_coverage_over_10.txt", sample = samples.names[samples.type == 'PE'].values.tolist()))
	return input
	
def bigwigoutput(wildcards):
  input = []
  input.extend(expand(outputdir + "HISAT2bigwig/{sample}_Aligned.sortedByCoord.out.bw", sample = samples.names[samples.type == 'PE'].values.tolist()))
  return input

def dexseqoutput(wildcards):
  input = []
  input.extend(expand(outputdir + "dexseq/{sample}.txt", sample = samples.names[samples.type == 'PE'].values.tolist()))
  return input
  
def jbrowse_output(wildcards):
  input = []
  input.extend(expand("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/trackList.json"))
  # input.extend(expand("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/output"))
  input.extend(expand("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/samples/{sample}.bw", sample = samples.names[samples.type == 'PE'].values.tolist()))
  input.extend(expand("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/samples/{sample}.bam", sample = samples.names[samples.type == 'PE'].values.tolist()))
  input.extend(expand("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/samples/{sample}.bam.bai", sample = samples.names[samples.type == 'PE'].values.tolist()))
  
  input.append("/var/www/html/jbrowse/" + os.path.basename(proj_dir) + "/trackList.json")
  return input

# def kb_output(wildcards):
# 	input = []
# 	input.extend(expand(outputdir + "kb/unfiltered/adata.h5ad", sample = samples.names[samples.type == 'PE'].values.tolist()))
# 	return input
  
	
## ------------------------------------------------------------------------------------ ##
## Target definitions
## ------------------------------------------------------------------------------------ ##
## Run all analyses
rule all:
	input:
		outputdir + "MultiQC/multiqc_report.html",
		bigwigoutput,
		# outputdir + "seurat/stringtie_seu.rds",
		outputdir + "kallisto/adata.h5ad"
		# stringtie_output,
		# outputdir + "seurat/legacy_unfiltered_seu.rds",
		# dexseqoutput
		# dbtss_output,
		# jbrowse_output
		# loom_file = outputdir + "velocyto/" + os.path.basename(proj_dir) + ".loom",
		# velocyto_seu = outputdir + "velocyto/" + "unfiltered_seu.rds",
		# loom = outputdir + "scenic/unfiltered.loom"
		# final_loom = outputdir + "scenic/unfiltered-final.loom"

rule setup:
	input:
		outputdir + "Rout/pkginstall_state.txt",
		outputdir + "Rout/softwareversions.done"

## Install R packages
rule pkginstall:
	input:
		script = "scripts/install_pkgs.R"
	output:
	  outputdir + "Rout/pkginstall_state.txt"
	params:
		flag = config["annotation"],
		ncores = config["ncores"],
		organism = config["organism"]
	priority:
		50
	conda:
		Renv
	log:
		outputdir + "Rout/install_pkgs.Rout"
	benchmark:
	  outputdir + "benchmarks/install_pkgs.txt"
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args outtxt='{output}' ncores='{params.ncores}' annotation='{params.flag}' organism='{params.organism}'" {input.script} {log}'''

## FastQC on original (untrimmed) files
rule runfastqc:
	input:
		expand(outputdir + "FastQC/{sample}_" + str(config["fqext1"]) + "_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()),
		expand(outputdir + "FastQC/{sample}_" + str(config["fqext2"]) + "_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()),
		expand(outputdir + "FastQC/{sample}_fastqc.zip", sample = samples.names[samples.type == 'SE'].values.tolist())

## Trimming and FastQC on trimmed files
rule runtrimming:
	input:
		expand(outputdir + "FastQC/{sample}_" + str(config["fqext1"]) + "_val_1_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()),
		expand(outputdir + "FastQC/{sample}_" + str(config["fqext2"]) + "_val_2_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()),
		expand(outputdir + "FastQC/{sample}_trimmed_fastqc.zip", sample = samples.names[samples.type == 'SE'].values.tolist())

## Salmon quantification
rule runsalmonquant:
	input:
		expand(outputdir + "salmon/{sample}/quant.sf", sample = samples.names.values.tolist())

## STAR alignment
rule runstar:
	input:
		expand(outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai", sample = samples.names.values.tolist()),
		expand(outputdir + "STARbigwig/{sample}_Aligned.sortedByCoord.out.bw", sample = samples.names.values.tolist())
		
## HISAT2 alignment
rule runhisat2:
	input:
		expand(outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai", sample = samples.names.values.tolist()),
		expand(outputdir + "HISAT2bigwig/{sample}_Aligned.sortedByCoord.out.bw", sample = samples.names.values.tolist())
		
## DBTSS coverage
rule rundbtss:
	input:
		expand(outputdir + "dbtss_coverage/{sample}/{sample}_dbtss_coverage.txt", sample = samples.names.values.tolist())

## List all the packages that were used by the R analyses
rule listpackages:
	log:
		outputdir + "Rout/list_packages.Rout"
	params:
		Routdir = outputdir + "Rout",
		outtxt = outputdir + "R_package_versions.txt",
		script = "scripts/list_packages.R"
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args Routdir='{params.Routdir}' outtxt='{params.outtxt}'" {params.script} {log}'''

## Print the versions of all software packages
rule softwareversions:
	output:
		touch(outputdir + "Rout/softwareversions.done")
	conda:
		"envs/environment.yaml"
	shell:
		"echo -n 'ARMOR version ' && cat version; "
		"salmon --version; kallisto version; trim_galore --version; "
		"echo -n 'cutadapt ' && cutadapt --version; "
		"fastqc --version; STAR --version; hisat2 --version; samtools --version; multiqc --version; "
		"bedtools --version"

## ------------------------------------------------------------------------------------ ##
## Reference preparation
## ------------------------------------------------------------------------------------ ##

## Generate Salmon index from merged cDNA and ncRNA files
rule salmonindex:
	input:
		txome = config["txome"]
	output:
		config["salmonindex"] + "/hash.bin"
	log:
		outputdir + "logs/salmon_index.log"
	benchmark:
		outputdir + "benchmarks/salmon_index.txt"
	params:
		salmonk = config["salmonk"],
		salmonoutdir = config["salmonindex"],
		anno = config["annotation"]
	conda:
		"envs/environment.yaml"
	shell:
	  """
	  if [ {params.anno} == "Gencode" ]; then
      echo 'Salmon version:\n' > {log}; salmon --version >> {log};
  	  salmon index -t {input.txome} -k {params.salmonk} -i {params.salmonoutdir} --gencode --type quasi

    else
  	  echo 'Salmon version:\n' > {log}; salmon --version >> {log};
      salmon index -t {input.txome} -k {params.salmonk} -i {params.salmonoutdir} --type quasi
    fi
    """
    
# kb ref -i transcriptome.idx -g transcripts_to_genes.txt -f1 cdna.fa dna.primary_assembly.fa.gz gtf.gz

## Generate linkedtxome mapping
rule linkedtxome:
	input:
		txome = config["txome"],
		gtf = config["gtf"],
		salmonidx = config["salmonindex"] + "/hash.bin",
		script = "scripts/generate_linkedtxome.R",
		install = outputdir + "Rout/pkginstall_state.txt"
	log:
		outputdir + "Rout/generate_linkedtxome.Rout"
	benchmark:
		outputdir + "benchmarks/generate_linkedtxome.txt"
	output:
		config["salmonindex"] + ".json"
	params:
		flag = config["annotation"],
		organism = config["organism"],
		release = str(config["release"]),
		build = config["build"]
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args transcriptfasta='{input.txome}' salmonidx='{input.salmonidx}' gtf='{input.gtf}' annotation='{params.flag}' organism='{params.organism}' release='{params.release}' build='{params.build}' output='{output}'" {input.script} {log}'''

## Generate STAR index
# rule starindex:
# 	input:
# 		genome = config["genome"],
# 		gtf = config["gtf"]
# 	output:
# 		config["STARindex"] + "/SA",
# 		config["STARindex"] + "/chrNameLength.txt"
# 	log:
# 		outputdir + "logs/STAR_index.log"
# 	benchmark:
# 		outputdir + "benchmarks/STAR_index.txt"
# 	params:
# 		STARindex = config["STARindex"],
# 		readlength = config["readlength"]
# 	conda:
# 		"envs/environment.yaml"
# 	threads:
# 		config["ncores"]
# 	shell:
# 		"echo 'STAR version:\n' > {log}; STAR --version >> {log}; "
# 		"STAR --runMode genomeGenerate --runThreadN {threads} --genomeDir {params.STARindex} "
# 		"--genomeFastaFiles {input.genome} --sjdbGTFfile {input.gtf} --sjdbOverhang {params.readlength}"

## ------------------------------------------------------------------------------------ ##
## Quality control
## ------------------------------------------------------------------------------------ ##
## FastQC, original reads
rule fastqc:
	input:
		fastq = FASTQdir + "{sample}." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "FastQC/{sample}_fastqc.zip"
	params:
		FastQC = outputdir + "FastQC"
	log:
		outputdir + "logs/fastqc_{sample}.log"
	benchmark:
		outputdir + "benchmarks/fastqc_{sample}.txt"
	conda:
		"envs/environment.yaml"
	threads:
		config["ncores"]
	shell:
		"echo 'FastQC version:\n' > {log}; fastqc --version >> {log}; "
		"fastqc -o {params.FastQC} -t {threads} {input.fastq}"

## FastQC, trimmed reads
rule fastqctrimmed:
	input:
		fastq = outputdir + "FASTQtrimmed/{sample}.fq.gz"
	output:
		outputdir + "FastQC/{sample}_fastqc.zip"
	params:
		FastQC = outputdir + "FastQC"
	log:
		outputdir + "logs/fastqc_trimmed_{sample}.log"
	benchmark:
		outputdir + "benchmarks/fastqc_trimmed_{sample}.txt"
	conda:
		"envs/environment.yaml"
	threads:
		config["ncores"]
	shell:
		"echo 'FastQC version:\n' > {log}; fastqc --version >> {log}; "
		"fastqc -o {params.FastQC} -t {threads} {input.fastq}"
		
## Rseqc gene body coverage plot
rule genebodycoverage:
	input:
		bigwig = outputdir + "HISAT2bigwig/{sample}_Aligned.sortedByCoord.out.bw"
	output:
		coverage_txt = outputdir + "rseqc/{sample}.geneBodyCoverage.txt"
	params:
		sample = outputdir + "rseqc/{sample}",
		bed = config["bed"]
	log:
		outputdir + "logs/genebodycoverage_{sample}.log"
	benchmark:
		outputdir + "benchmarks/genebodycoverage_{sample}.txt"
	conda:
		"envs/environment.yaml"
	threads:
		config["ncores"]
	shell:
		"echo 'geneBody_coverage.py version:\n' > {log}; geneBody_coverage.py --version >> {log}; "
		"geneBody_coverage2.py -r {params.bed} -i {input.bigwig}  -o {params.sample}"

# The config.yaml files determines which steps should be performed
def multiqc_input(wildcards):
	input = []
	input.extend(expand(outputdir + "FastQC/{sample}_fastqc.zip", sample = samples.names[samples.type == 'SE'].values.tolist()))
	input.extend(expand(outputdir + "FastQC/{sample}_" + str(config["fqext1"]) + "_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()))
	input.extend(expand(outputdir + "FastQC/{sample}_" + str(config["fqext2"]) + "_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()))
	if config["run_genebodycoverage"]:
	  input.extend(expand(outputdir + "rseqc/{sample}." + "geneBodyCoverage.txt", sample = samples.names[samples.type == 'PE'].values.tolist()))
	if config["run_SALMON"]:
		input.extend(expand(outputdir + "salmon/{sample}/quant.sf", sample = samples.names.values.tolist()))
	if config["run_trimming"]:
		input.extend(expand(outputdir + "FASTQtrimmed/{sample}_trimmed.fq.gz", sample = samples.names[samples.type == 'SE'].values.tolist()))
		input.extend(expand(outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext1"]) + "_val_1.fq.gz", sample = samples.names[samples.type == 'PE'].values.tolist()))
		input.extend(expand(outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext2"]) + "_val_2.fq.gz", sample = samples.names[samples.type == 'PE'].values.tolist()))
		input.extend(expand(outputdir + "FastQC/{sample}_trimmed_fastqc.zip", sample = samples.names[samples.type == 'SE'].values.tolist()))
		input.extend(expand(outputdir + "FastQC/{sample}_" + str(config["fqext1"]) + "_val_1_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()))
		input.extend(expand(outputdir + "FastQC/{sample}_" + str(config["fqext2"]) + "_val_2_fastqc.zip", sample = samples.names[samples.type == 'PE'].values.tolist()))
	if config["run_STAR"]:
		input.extend(expand(outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai", sample = samples.names.values.tolist()))
	if config["run_HISAT2"]:
		input.extend(expand(outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai", sample = samples.names.values.tolist()))
	return input

## Determine the input directories for MultiQC depending on the config file
def multiqc_params(wildcards):
	param = [outputdir + "FastQC"]
	if config["run_SALMON"]:
		param.append(outputdir + "salmon")
	if config["run_trimming"]:
		param.append(outputdir + "FASTQtrimmed")
	if config["run_STAR"]:
		param.append(outputdir + "STAR")
	if config["run_HISAT2"]:
		param.append(outputdir + "HISAT2")
	return param

## MultiQC
rule multiqc:
	input:
		multiqc_input
	output:
		outputdir + "MultiQC/multiqc_report.html"
	params:
		inputdirs = multiqc_params,
		MultiQCdir = outputdir + "MultiQC"
	log:
		outputdir + "logs/multiqc.log"
	benchmark:
		outputdir + "benchmarks/multiqc.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'MultiQC version:\n' > {log}; multiqc --version >> {log}; "
		"multiqc {params.inputdirs} -f -o {params.MultiQCdir}"


## ------------------------------------------------------------------------------------ ##
## Adapter trimming
## ------------------------------------------------------------------------------------ ##
# TrimGalore!
rule trimgaloreSE:
	input:
		fastq = FASTQdir + "{sample}." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "FASTQtrimmed/{sample}_trimmed.fq.gz"
	params:
		FASTQtrimmeddir = outputdir + "FASTQtrimmed"
	log:
		outputdir + "logs/trimgalore_{sample}.log"
	benchmark:
		outputdir + "benchmarks/trimgalore_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'TrimGalore! version:\n' > {log}; trim_galore --version >> {log}; "
		"trim_galore -q 20 --phred33 --length 20 -o {params.FASTQtrimmeddir} --path_to_cutadapt cutadapt {input.fastq}"

rule trimgalorePE:
	input:
		fastq1 = FASTQdir + "{sample}_" + str(config["fqext1"]) + "." + str(config["fqsuffix"]) + ".gz",
		fastq2 = FASTQdir + "{sample}_" + str(config["fqext2"]) + "." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext1"]) + "_val_1.fq.gz",
		outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext2"]) + "_val_2.fq.gz"
	params:
		FASTQtrimmeddir = outputdir + "FASTQtrimmed"
	log:
		outputdir + "logs/trimgalore_{sample}.log"
	benchmark:
		outputdir + "benchmarks/trimgalore_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'TrimGalore! version:\n' > {log}; trim_galore --version >> {log}; "
		"trim_galore -q 20 --phred33 --length 20 -o {params.FASTQtrimmeddir} --path_to_cutadapt cutadapt "
		"--paired {input.fastq1} {input.fastq2}"

## ------------------------------------------------------------------------------------ ##
## HISAT2 mapping
## ------------------------------------------------------------------------------------ ##
## Genome mapping with HISAT2
rule HISAT2PE:
	input:
		fastq1 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext1"]) + "_val_1.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext1"]) + "." + str(config["fqsuffix"]) + ".gz",
		fastq2 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext2"]) + "_val_2.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext2"]) + "." + str(config["fqsuffix"]) + ".gz"
	output:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.out.bam"
	threads:
		config["ncores"]
	log:
		version = outputdir + "logs/HISAT2_{sample}.log",
		stats = outputdir + "HISAT2" + "/HISAT2_{sample}_stats.txt"
	benchmark:
		outputdir + "benchmarks/HISAT2_{sample}.txt"
	params:
		HISAT2index = config["HISAT2index"],
		HISAT2dir = outputdir + "HISAT2"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'hisat2 --version:\n' > {log.version}; hisat2 --version >> {log.version}; "
		"hisat2 --new-summary --pen-noncansplice 20 --threads {threads} --mp 1,0 --sp 3,1 -x {params.HISAT2index} -1 {input.fastq1} -2 {input.fastq2} 2> {log.stats} | samtools view -Sbo {output.bam}"

# convert and sort sam files
rule bamsort:
	input:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.out.bam"
	output:
		sorted_bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	log:
		outputdir + "logs/samtools_sort_{sample}.log"
	benchmark:
		outputdir + "benchmarks/samtools_sort_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'samtools version:\n' > {log}; samtools --version >> {log}; "
		"samtools sort -O bam -o {output.sorted_bam} {input.bam}"

## Index bam files
rule bamindexhisat2:
	input:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	output:
		outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai"
	log:
		outputdir + "logs/samtools_index_{sample}.log"
	benchmark:
		outputdir + "benchmarks/samtools_index_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'samtools version:\n' > {log}; samtools --version >> {log}; "
		"samtools index {input.bam}"

## Convert BAM files to bigWig
rule bigwighisat2:
	input:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam",
		chrl = os.path.dirname(config["HISAT2index"]) + "/chrNameLength.txt"
	output:
		outputdir + "HISAT2bigwig/{sample}_Aligned.sortedByCoord.out.bw"
	params:
		HISAT2bigwigdir = outputdir + "HISAT2bigwig"
	log:
		outputdir + "logs/bigwig_{sample}.log"
	benchmark:
		outputdir + "benchmarks/bigwig_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'bedtools version:\n' > {log}; bedtools --version >> {log}; "
		"bedtools genomecov -split -ibam {input.bam} -bg | LC_COLLATE=C sort -k1,1 -k2,2n > "
		"{params.HISAT2bigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph; "
		"bedGraphToBigWig {params.HISAT2bigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph "
		"{input.chrl} {output}; "
		#"rm -f {params.HISAT2bigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph"

## ------------------------------------------------------------------------------------ ##
## Stringtie
## ------------------------------------------------------------------------------------ ##
# Transcript assembly using StringTie
rule stringtie:
	input:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	output:
		gtf = outputdir + "stringtie/{sample}/{sample}.gtf"
	log:
		outputdir + "logs/stringtie_{sample}.log"
	benchmark:
		outputdir + "benchmarks/stringtie_{sample}.txt"
	threads:
		config["ncores"]
	params:
		stringtiegtf = config["gtf"],
		stringtiedir = outputdir + "stringtie"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'stringtie version:\n' > {log}; stringtie --version >> {log}; "
		"stringtie {input.bam} -G {params.stringtiegtf} -x MT -eB -o {output.gtf}"

## ------------------------------------------------------------------------------------ ##
## DEXSeq
## ------------------------------------------------------------------------------------ ##

# Transcript assembly using dexseq
rule dexseq:
	input:
		bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	output:
		txt = outputdir + "dexseq/{sample}.txt"
	log:
		outputdir + "logs/dexseq_{sample}.log"
	benchmark:
		outputdir + "benchmarks/dexseq_{sample}.txt"
	threads:
		config["ncores"]
	params:
		dexseqgtf = config["exon_collapsed_gff"],
		dexseqdir = outputdir + "dexseq"
	conda:
		"envs/environment.yaml"
	shell:
		# "echo 'dexseq version:\n' > {log}; dexseq --version >> {log}; "
		"python scripts/dexseq_count.py -r pos -p yes -s no -f bam {params.dexseqgtf} {input.bam} {output.txt}"

## ------------------------------------------------------------------------------------ ##
## kb abundance estimation
## ------------------------------------------------------------------------------------ ##

rule kallisto_batch:
  input:
    metatxt = config["metatxt"]
  output:
    outputdir + "kallisto/smart-seq_batch.txt"
	log:
		outputdir + "logs/kallisto.log"
	benchmark:
		outputdir + "benchmarks/kallisto.txt"
	threads:
		config["ncores"]
	run:
		# make batch
		# samples = pd.read_csv(config["metatxt"], sep='\t')
		batch_table = samples[['names', 'type']]
		batch_table = batch_table.assign(R1="../data/FASTQ/"+batch_table['names']+"_R1.fastq.gz", R2="../data/FASTQ/"+batch_table['names']+"_R2.fastq.gz")
		batch_table = batch_table.drop(['type'], axis=1)
		batch_table.to_csv(output[0], sep = "\t", index = False, header = False)

# Estimate abundances with kb
rule kallistoPE:
	input:
	  kallistobatch = outputdir + "kallisto/smart-seq_batch.txt"
	output:
		outputdir + "kallisto/matrix.abundance.mtx"
	log:
		outputdir + "logs/kallisto.log"
	benchmark:
		outputdir + "benchmarks/kallisto.txt"
	threads:
		config["ncores"]
	params:
		kallistoindex = config["kallistoindex"],
		kallistodir = outputdir + "kallisto",
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'kallisto version:\n' > {log}; kallisto version >> {log}; "
		"kallisto pseudo --quant -i {params.kallistoindex} -o {params.kallistodir} -b {input.kallistobatch} -t {threads}"
		
# convert kallisto output to anndata
rule kallisto2adata:
	input:
	  matrix = outputdir + "kallisto/matrix.abundance.mtx",
	  cells = outputdir + "kallisto/matrix.cells",
	  transcripts = outputdir + "kallisto/transcripts.txt",
	  script = "scripts/make_adata.py"
	output:
		outputdir + "kallisto/adata.h5ad"
	log:
		outputdir + "logs/kallisto.log"
	benchmark:
		outputdir + "benchmarks/kallisto.txt"
	threads:
		config["ncores"]
	params:
		kallistodir = outputdir + "kallisto/",
	conda:
		"envs/environment.yaml"
	shell:
		"python {input.script} -m {input.matrix} -c {input.cells} -t {input.transcripts} --outdir {params.kallistodir}"

## ------------------------------------------------------------------------------------ ##
## Salmon abundance estimation
## ------------------------------------------------------------------------------------ ##
# Estimate abundances with Salmon
rule salmonSE:
	input:
		index = config["salmonindex"] + "/hash.bin",
		fastq = outputdir + "FASTQtrimmed/{sample}_trimmed.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "salmon/{sample}/quant.sf"
	log:
		outputdir + "logs/salmon_{sample}.log"
	benchmark:
		outputdir + "benchmarks/salmon_{sample}.txt"
	threads:
		config["ncores"]
	params:
		salmonindex = config["salmonindex"],
		fldMean = config["fldMean"],
		fldSD = config["fldSD"],
		salmondir = outputdir + "salmon"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'Salmon version:\n' > {log}; salmon --version >> {log}; "
		"salmon quant -i {params.salmonindex} -l A -r {input.fastq} "
		"-o {params.salmondir}/{wildcards.sample} --seqBias --gcBias "
		"--fldMean {params.fldMean} --fldSD {params.fldSD} -p {threads}"

rule salmonPE:
	input:
		index = config["salmonindex"] + "/hash.bin",
		fastq1 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext1"]) + "_val_1.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext1"]) + "." + str(config["fqsuffix"]) + ".gz",
		fastq2 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext2"]) + "_val_2.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext2"]) + "." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "salmon/{sample}/quant.sf"
	log:
		outputdir + "logs/salmon_{sample}.log"
	benchmark:
		outputdir + "benchmarks/salmon_{sample}.txt"
	threads:
		config["ncores"]
	params:
		salmonindex = config["salmonindex"],
		fldMean = config["fldMean"],
		fldSD = config["fldSD"],
		salmondir = outputdir + "salmon"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'Salmon version:\n' > {log}; salmon --version >> {log}; "
		"salmon quant -i {params.salmonindex} -l A -1 {input.fastq1} -2 {input.fastq2} "
		"-o {params.salmondir}/{wildcards.sample} --seqBias --gcBias "
		"--fldMean {params.fldMean} --fldSD {params.fldSD} -p {threads}"

## ------------------------------------------------------------------------------------ ##
## STAR mapping
## ------------------------------------------------------------------------------------ ##
## Genome mapping with STAR
# rule starSE:
# 	input:
# 		index = config["STARindex"] + "/SA",
# 		fastq = outputdir + "FASTQtrimmed/{sample}_trimmed.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}." + str(config["fqsuffix"]) + ".gz"
# 	output:
# 		outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
# 	threads:
# 		config["ncores"]
# 	log:
# 		outputdir + "logs/STAR_{sample}.log"
# 	benchmark:
# 		outputdir + "benchmarks/STAR_{sample}.txt"
# 	params:
# 		STARindex = config["STARindex"],
# 		STARdir = outputdir + "STAR"
# 	conda:
# 		"envs/environment.yaml"
# 	shell:
# 		"echo 'STAR version:\n' > {log}; STAR --version >> {log}; "
# 		"STAR --genomeDir {params.STARindex} --readFilesIn {input.fastq} "
# 		"--runThreadN {threads} --outFileNamePrefix {params.STARdir}/{wildcards.sample}/{wildcards.sample}_ "
# 		"--outSAMtype BAM SortedByCoordinate --readFilesCommand gunzip -c"

rule starPE:
	input:
		index = config["STARindex"] + "/SA",
		fastq1 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext1"]) + "_val_1.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext1"]) + "." + str(config["fqsuffix"]) + ".gz",
		fastq2 = outputdir + "FASTQtrimmed/{sample}_" + str(config["fqext2"]) + "_val_2.fq.gz" if config["run_trimming"] else FASTQdir + "{sample}_" + str(config["fqext2"]) + "." + str(config["fqsuffix"]) + ".gz"
	output:
		outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	threads:
		config["ncores"]
	log:
		outputdir + "logs/STAR_{sample}.log"
	benchmark:
		outputdir + "benchmarks/STAR_{sample}.txt"
	params:
		STARindex = config["STARindex"],
		STARdir = outputdir + "STAR"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'STAR version:\n' > {log}; STAR --version >> {log}; "
		"STAR --genomeDir {params.STARindex} --readFilesIn {input.fastq1} {input.fastq2} "
		"--runThreadN {threads} --outFileNamePrefix {params.STARdir}/{wildcards.sample}/{wildcards.sample}_ "
		"--outSAMtype BAM SortedByCoordinate --outSAMattrIHstart 0 --readFilesCommand gunzip -c"

## Index bam files
rule bamindex:
	input:
		bam = outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	output:
		outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam.bai"
	log:
		outputdir + "logs/samtools_index_{sample}.log"
	benchmark:
		outputdir + "benchmarks/samtools_index_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'samtools version:\n' > {log}; samtools --version >> {log}; "
		"samtools index {input.bam}"

## Convert BAM files to bigWig
rule bigwig:
	input:
		bam = outputdir + "STAR/{sample}/{sample}_Aligned.sortedByCoord.out.bam",
		chrl = config["STARindex"] + "/chrNameLength.txt"
	output:
		outputdir + "STARbigwig/{sample}_Aligned.sortedByCoord.out.bw"
	params:
		STARbigwigdir = outputdir + "STARbigwig"
	log:
		outputdir + "logs/bigwig_{sample}.log"
	benchmark:
		outputdir + "benchmarks/bigwig_{sample}.txt"
	conda:
		"envs/environment.yaml"
	shell:
		"echo 'bedtools version:\n' > {log}; bedtools --version >> {log}; "
		"bedtools genomecov -split -ibam {input.bam} -bg | LC_COLLATE=C sort -k1,1 -k2,2n > "
		"{params.STARbigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph; "
		"bedGraphToBigWig {params.STARbigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph "
		"{input.chrl} {output}; rm -f {params.STARbigwigdir}/{wildcards.sample}_Aligned.sortedByCoord.out.bedGraph"

## ------------------------------------------------------------------------------------ ##
## Transcript quantification
## ------------------------------------------------------------------------------------ ##

## tximeta
rule tximeta:
	input:
	  outputdir + "Rout/pkginstall_state.txt",
		expand(outputdir + "salmon/{sample}/quant.sf", sample = samples.names.values.tolist()),
		metatxt = config["metatxt"],
		salmonidx = config["salmonindex"] + "/hash.bin",
		json = config["salmonindex"] + ".json",
		script = "scripts/run_tximeta.R"
	output:
		outputdir + "outputR/tximeta.rds"
	log:
		outputdir + "Rout/tximeta.Rout"
	benchmark:
		outputdir + "benchmarks/tximeta.txt"
	params:
		salmondir = outputdir + "salmon",
		flag = config["annotation"],
		organism = config["organism"]
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args salmondir='{params.salmondir}' json='{input.json}' metafile='{input.metatxt}' outrds='{output}' annotation='{params.flag}' organism='{params.organism}'" {input.script} {log}'''

## rna velocity
rule velocyto:
	input:
	  outputdir + "Rout/pkginstall_state.txt",
		bam_files = expand(outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam", sample = samples.names.values.tolist()),
	output:
		loom_file = outputdir + "velocyto/" + os.path.basename(proj_dir) + ".loom"
	log:
		outputdir + "Rout/velocyto.Rout"
	benchmark:
		outputdir + "benchmarks/velocyto.txt"
	params:
	  repeat_mask = config["repeat_mask"],
	  proj_name = os.path.basename(proj_dir),
	  gtf = config["gtf"],
	  loom_dir = outputdir + "velocyto/"
	conda:
		Renv
	shell:
		"velocyto run-smartseq2 -o {params.loom_dir} -m {params.repeat_mask} -e {params.proj_name} {input.bam_files} {params.gtf}"
		
## tximport
rule tximport:
	input:
	  outputdir + "Rout/pkginstall_state.txt",
		expand(outputdir + "stringtie/{sample}/{sample}.gtf", sample = samples.names.values.tolist()),
		script = "scripts/run_tximport.R"
	output:
		outrds = outputdir + "seurat/stringtie_seu.rds",
	log:
		outputdir + "Rout/tximport.Rout"
	benchmark:
		outputdir + "benchmarks/tximport.txt"
	params:
		stringtiedir = outputdir + "stringtie",
		organism = config["organism"]
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args stringtiedir='{params.stringtiedir}' proj_dir='{proj_dir}' outrds='{output.outrds}' organism='{params.organism}'" {input.script} {log}'''

## rna velocity on a seurat object
rule velocyto_seurat:
  input:
  	loom_file = outputdir + "velocyto/" + os.path.basename(proj_dir) + ".loom",
  	seu_file = outputdir + "seurat/unfiltered_seu.rds",
  	script = "scripts/compute_velocity.R"
  output:
    outputdir + "velocyto/unfiltered_seu.rds"
	log:
		outputdir + "Rout/velocyto.Rout"
	benchmark:
		outputdir + "benchmarks/veloctyo_seurat.txt"
	params:
		organism = config["organism"]
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args loom_path='{input.loom_file}' proj_dir='{proj_dir}' outrds='{output}' organism='{params.organism}'" {input.script} {log}'''


## ------------------------------------------------------------------------------------ ##
## SCENIC
## ------------------------------------------------------------------------------------ ##

include: "rules/scenic.smk"

## ------------------------------------------------------------------------------------ ##
## Input variable check
## ------------------------------------------------------------------------------------ ##
def geneset_param(wildcards):
	if config["run_camera"]:
                gs = config["genesets"].replace(" ", "") if config["genesets"] is not None else "NOTDEFINED"
		return "genesets='" + gs + "'"
	else:
		return ""


## check design matrix and contrasts
rule checkinputs:
    input:
        "config.yaml",
        script = "scripts/check_input.R"
    output:
        outputdir + "Rout/check_input.txt"
    log:
        outputdir + "Rout/check_input.Rout"
    benchmark:
    	outputdir + "benchmarks/check_input.txt"
    params:
        gtf = config["gtf"],
        genome = config["genome"],
        txome = config["txome"],
        fastqdir = config["FASTQ"],
        metatxt = config["metatxt"],
        design = config["design"].replace(" ", "") if config["design"] is not None else "NOTDEFINED",
        contrast = config["contrast"].replace(" ", "") if config["contrast"] is not None else "NOTDEFINED",
        annotation = config["annotation"].replace(" ", "") if config["annotation"] is not None else "NOTDEFINED",
        genesets = geneset_param,
        fqsuffix = str(config["fqsuffix"]),
        fqext1 = str(config["fqext1"]),
        fqext2 = str(config["fqext2"]),
        run_camera = str(config["run_camera"]),
        organism = config["organism"]    
    conda:
	    Renv
    shell:
        '''{Rbin} CMD BATCH --no-restore --no-save "--args metafile='{params.metatxt}' design='{params.design}' contrast='{params.contrast}' outFile='{output}' gtf='{params.gtf}' genome='{params.genome}' fastqdir='{params.fastqdir}' fqsuffix='{params.fqsuffix}' fqext1='{params.fqext1}' fqext2='{params.fqext2}' txome='{params.txome}' run_camera='{params.run_camera}' organism='{params.organism}' {params.genesets} annotation='{params.annotation}'" {input.script} {log};
        cat {output}
        '''
       

## ------------------------------------------------------------------------------------ ##
## Differential expression
## ------------------------------------------------------------------------------------ ##
rule edgeR:
	input:
		outputdir + "Rout/pkginstall_state.txt",
		rds = outputdir + "seurat/unfiltered_seu.rds",
		script = "scripts/run_render.R",
		template = "scripts/edgeR_dge.Rmd"
	output:
		html = outputdir + "outputR/edgeR_dge.html",
		rds = outputdir + "outputR/edgeR_dge.rds"
	params:
		directory = outputdir + "outputR",
		organism = config["organism"],        
                design = config["design"].replace(" ", "") if config["design"] is not None else "",
                contrast = config["contrast"].replace(" ", "") if config["contrast"] is not None else "",
		genesets = geneset_param
	log:
		outputdir + "Rout/run_dge_edgeR.Rout"
	benchmark:
		outputdir + "benchmarks/run_dge_edgeR.txt"
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args se='{input.rds}' organism='{params.organism}' design='{params.design}' contrast='{params.contrast}' {params.genesets} rmdtemplate='{input.template}' outputdir='{params.directory}' outputfile='edgeR_dge.html'" {input.script} {log}'''

## ------------------------------------------------------------------------------------ ##
## Differential transcript usage
## ------------------------------------------------------------------------------------ ##
## DRIMSeq
rule DRIMSeq:
	input:
	  outputdir + "Rout/pkginstall_state.txt",
		rds = outputdir + "seurat/unfiltered_seu.rds",
		script = "scripts/run_render.R",
		template = "scripts/DRIMSeq_dtu.Rmd"
	output:
		html = outputdir + "outputR/DRIMSeq_dtu.html",
		rds = outputdir + "outputR/DRIMSeq_dtu.rds"
	params:
		directory = outputdir + "outputR",
		organism = config["organism"],
		ncores = config["ncores"], design = config["design"].replace(" ", "") if config["design"] is not None else "", contrast = config["contrast"].replace(" ", "") if config["contrast"] is not None else ""
	log:
		outputdir + "Rout/run_dtu_drimseq.Rout"
	benchmark:
		outputdir + "benchmarks/run_dtu_drimseq.txt"
	conda:
		Renv
	threads:
		config["ncores"]
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args se='{input.rds}' design='{params.design}' contrast='{params.contrast}' ncores='{params.ncores}' rmdtemplate='{input.template}' outputdir='{params.directory}' outputfile='DRIMSeq_dtu.html'" {input.script} {log}'''

## ------------------------------------------------------------------------------------ ##
## shiny app
## ------------------------------------------------------------------------------------ ##
def shiny_input(wildcards):
	input = [outputdir + "Rout/pkginstall_state.txt"]
	if config["run_STAR"]:
		input.extend(expand(outputdir + "STARbigwig/{sample}_Aligned.sortedByCoord.out.bw", sample = samples.names.values.tolist()))
	if config["run_HISAT2"]:
		input.extend(expand(outputdir + "HISAT2bigwig/{sample}_Aligned.sortedByCoord.out.bw", sample = samples.names.values.tolist()))
	return input

def shiny_params(wildcards):
	param = ["outputdir='" + outputdir + "outputR'"]
	if config["run_STAR"]:
		param.append("bigwigdir='" + outputdir + "STARbigwig'")
	if config["run_HISAT2"]:
		param.append("bigwigdir='" + outputdir + "HISAT2bigwig'")
	return param

## shiny
rule shiny:
	input:
		shiny_input,
		rds = outputdir + "outputR/DRIMSeq_dtu.rds" if config["run_DRIMSeq"]
			else outputdir + "outputR/edgeR_dge.rds",
		script = "scripts/run_render.R",
		gtf = config["gtf"],
		template = "scripts/prepare_shiny.Rmd"
	output:
		html = outputdir + "outputR/prepare_shiny.html",
		rds = outputdir + "outputR/shiny_sce.rds"
	params:
		p = shiny_params
	log:
		outputdir + "Rout/prepare_shiny.Rout"
	benchmark:
		outputdir + "benchmarks/prepare_shiny.txt"
	conda:
		Renv
	shell:
		'''{Rbin} CMD BATCH --no-restore --no-save "--args se='{input.rds}' gtffile='{input.gtf}' rmdtemplate='{input.template}' outputfile='prepare_shiny.html' {params.p}" {input.script} {log}'''
		
## ------------------------------------------------------------------------------------ ##
## dbtss coverage mapping
## ------------------------------------------------------------------------------------ ##
## compute coverage from dbtss
rule dbtss:
	input:
		sorted_bam = outputdir + "HISAT2/{sample}/{sample}_Aligned.sortedByCoord.out.bam"
	output:
		coverage_txt = outputdir + "dbtss_coverage/{sample}_dbtss_coverage_over_10.txt"
	threads:
		config["ncores"]
	log:
		outputdir + "logs/dbtss_{sample}.log"
	benchmark:
		outputdir + "benchmarks/dbtss_{sample}.txt"
	params:
		dbtss_bed = config["dbtss_bed"],
		genome_file = config["chrom_sizes"]
	conda:
		"envs/environment.yaml"
	shell:
	  "bedtools coverage -sorted -s -g {params.genome_file} -a {params.dbtss_bed} -b {input.sorted_bam} | awk '$4 > 10 {{print}}' > {output.coverage_txt}"

## ------------------------------------------------------------------------------------ ##
## configure jbrowse
## ------------------------------------------------------------------------------------ ##

include: "rules/jbrowse.smk"

## ------------------------------------------------------------------------------------ ##
## Success and failure messages
## ------------------------------------------------------------------------------------ ##
onsuccess:
	print("Success! The Snakemake workflow is completed.")

onerror:
	print("Error! The Snakemake workflow aborted.")

