PANDOC = pandoc -f markdown

SRC = $(wildcard *.md)
PDF = $(SRC:.md=.pdf)
TEX = $(SRC:.md=.tex)
HTM = $(SRC:.md=.htm)

# only build PDF by default
pdf: $(PDF)

tex: $(TEX)

htm: $(HTM)

all: pdf tex htm

%.tex: %.md
	$(PANDOC) $< -o $@ 

%.pdf: %.md
	$(PANDOC) $< -o $@ 

%.htm: %.md
	$(PANDOC) $< -o $@ 

clean:
	-rm -f $(PDF) $(TEX) $(HTM)
