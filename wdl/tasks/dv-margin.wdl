version 1.0

task dv_t {
  input {
      Int threads
      File reference
	  File bamAlignment
	  File bamAlignmentIndex
      String dvModel = "ONT_R104"
      Boolean oneChr = false
	  Int memSizeGb = 64
	  Int diskSizeGb = 100
      Int preemptible = 0
      File? resourceLogScript
  }  

  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace

    ## run a recurrent "top" in the background to monitor resource usage
    if [ ~{resourceLogScript} != "" ]
    then
        bash ~{resourceLogScript} 20 top.log &
    fi

    ln -s ~{reference} ref.fa
    samtools faidx ref.fa

    ln -s ~{bamAlignment} reads.bam
    ln -s ~{bamAlignmentIndex} reads.bam.bai

    ## if BAM has reads only for one chromosome
    ## figure out which one and add argument
    REGION_ARG=""
    if [ ~{oneChr} == true ]
    then
        CONTIG_ID=`head -1 < <(samtools view ~{bamAlignment}) | cut -f3`
        REGION_ARG="--regions $CONTIG_ID"
    fi

    ## run DeepVariant
    /opt/deepvariant/bin/run_deepvariant \
        --model_type ~{dvModel} \
        --ref ref.fa \
        --reads reads.bam \
        --output_vcf dv.vcf.gz $REGION_ARG \
        --num_shards ~{threads}
  >>>

  output {
	  File dvVcf = "dv.vcf.gz"
      File? toplog = "top.log"
  }

  runtime {
    preemptible: preemptible
    docker: "registry-vpc.miracle.ac.cn/gznl/google_deepvariant:cl508467184"
    cpu: threads
	memory: memSizeGb + " GB"
	disks: "local-disk " + diskSizeGb + " SSD"
  }
}

task margin_t {
  input {
      File reference
      File vcfFile
	  File bamAlignment
	  File bamAlignmentIndex
      String sampleName
      Int threads
      String marginOtherArgs = ""
	  Int memSizeGb = 64
	  Int diskSizeGb = 100
      File? resourceLogScript
  }  

  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace

    ## run a recurrent "top" in the background to monitor resource usage
    if [ ~{resourceLogScript} != "" ]
    then
        bash ~{resourceLogScript} 20 top.log &
    fi

    ln -s ~{reference} ref.fa
    samtools faidx ref.fa

    ln -s ~{bamAlignment} reads.bam
    ln -s ~{bamAlignmentIndex} reads.bam.bai
    
    # mkdir output/
    margin phase reads.bam ref.fa ~{vcfFile} /opt/margin/params/phase/allParams.haplotag.ont-r104q20.json -t ~{threads} ~{marginOtherArgs} -o output/~{sampleName}

    bgzip output/~{sampleName}.phased.vcf

    samtools index -@ ~{threads} output/~{sampleName}.haplotagged.bam
  >>>

  output {
      File phasedVcf = "output/~{sampleName}.phased.vcf.gz"
      File haplotaggedBam = "output/~{sampleName}.haplotagged.bam"
      File haplotaggedBamIdx = "output/~{sampleName}.haplotagged.bam.bai"
      File? toplog = "top.log"
  }

  runtime {
    preemptible: 2
    docker: "registry-vpc.miracle.ac.cn/gznl/mkolmogo_card_harmonize_vcf:0.1"
    cpu: threads
	memory: memSizeGb + " GB"
	disks: "local-disk " + diskSizeGb + " SSD"
  }
}

task mergeVCFs {
  input {
      Array[File] vcfFiles
      String outname = "merged"
	  Int memSizeGb = 6
	  Int diskSizeGb = round(size(vcfFiles, 'G')) + 20
  }  

  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace

    mkdir bcftools.tmp
    bcftools concat -n ~{sep=" " vcfFiles} | bcftools sort -T bcftools.tmp -O z -o ~{outname}.vcf.gz -
    bcftools index -t -o ~{outname}.vcf.gz.tbi ~{outname}.vcf.gz
  >>>

  output {
      File vcf = "~{outname}.vcf.gz"
      File vcfIndex = "~{outname}.vcf.gz.tbi"
  }

  runtime {
    preemptible: 2
    docker: "registry-vpc.miracle.ac.cn/gznl/quay.io_biocontainers_bcftools:1.3.1"
    cpu: 1
	memory: memSizeGb + " GB"
	disks: "local-disk " + diskSizeGb + " SSD"
  }
}
