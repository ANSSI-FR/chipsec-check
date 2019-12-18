TEX       := pdflatex
PDF_FLAGS := -interaction nonstopmode -halt-on-error -file-line-error

.PHONY: clean

procedure-de-tests.pdf: procedure-de-tests.tex
	${TEX} ${PDF_FLAGS} $<
	${TEX} ${PDF_FLAGS} $<

clean:
	rm -f *.aux *.log *.out *.pdf *.toc *.fmt
