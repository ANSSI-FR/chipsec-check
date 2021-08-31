PANDOC = pandoc -f markdown

SRC = $(wildcard *.md)
PDF = $(addprefix output/, $(SRC:.md=.pdf))
TEX = $(addprefix output/, $(SRC:.md=.tex))
HTM = $(addprefix output/, $(SRC:.md=.htm))

default: pdf htm

all: pdf tex htm

pdf: $(PDF)

tex: $(TEX)

htm: $(HTM)

output/%.tex: %.md
	$(PANDOC) $< -o $@ 

output/%.pdf: %.md
	$(PANDOC) $< -o $@ 

output/%.htm: %.md
	$(PANDOC) $< -o $@ 

clean:
	-rm -f $(PDF) $(TEX) $(HTM)
