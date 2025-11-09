compile:
	xelatex -interaction=nonstopmode main.tex && biber main && xelatex -interaction=nonstopmode main.tex && xelatex -interaction=nonstopmode main.tex


.PHONY: compile clean

commit:
	git add . && git commit -m "update" && git push