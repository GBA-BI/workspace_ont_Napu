version 1.0

task sniffles_t {
  input {
    Int threads = 16
	File bamAlignment
	File bamAlignmentIndex
	File? vntrAnnotations
	Int minSvLen = 25
	Int memSizeGb = 50
	Int diskSizeGb = 50
    File? resourceLogScript
  }

  String trfString = if defined(vntrAnnotations) then "--tandem-repeats " else ""
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

    ln -s ~{bamAlignment} reads.bam
    ln -s ~{bamAlignmentIndex} reads.bam.bai
    
    sniffles -i reads.bam -v sniffles.vcf -t ~{threads} ~{trfString}~{vntrAnnotations} --minsvlen ~{minSvLen} 2>&1 | tee sniffles.log
  >>>

  output {
	File snifflesVcf = "sniffles.vcf"
	File snifflesLog = "sniffles.log"
    File? toplog = "top.log"
  }

  runtime {
    preemptible: 2
    docker: "registry-vpc.miracle.ac.cn/gznl/mkolmogo_card_sniffles:2.0.3"
    cpu: threads
	memory: memSizeGb + " GB"
	disks: "local-disk " + diskSizeGb + " SSD"
  }
}
