DOC := filter-explainer.md
DEST := filter-explainer.html

.PHONY: all clean
all: $(DEST)

clean:
	rm -f $(DEST)

%.html: %.md
	pandoc --number-sections --reference-links --reference-location=document -o $@ -f markdown -t html5 $<
