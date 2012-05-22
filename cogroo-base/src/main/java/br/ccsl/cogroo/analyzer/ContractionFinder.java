package br.ccsl.cogroo.analyzer;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.ListIterator;

import opennlp.tools.namefind.NameFinderME;
import opennlp.tools.util.Span;
import br.ccsl.cogroo.ContractionUtility;
import br.ccsl.cogroo.config.Analyzers;
import br.ccsl.cogroo.text.Document;
import br.ccsl.cogroo.text.Sentence;
import br.ccsl.cogroo.text.Token;
import br.ccsl.cogroo.text.impl.TokenImpl;
import br.ccsl.cogroo.util.TextUtils;

/**
 * The <code>ContractionFinder</code> class searches for contractions in a given
 * sentence and then expands them to their primitive form.
 * 
 */
public class ContractionFinder implements AnalyzerI {

  private NameFinderME contractionFinder;

  public ContractionFinder(NameFinderME contractionFinder) {
    this.contractionFinder = contractionFinder;
  }

  public void analyze(Document document) {
    List<Sentence> sentences = document.getSentences();

    for (Sentence sentence : sentences) {
      Span[] contractionsSpan = contractionFinder.find(TextUtils
          .tokensToString(sentence.getTokens()));
      List<Token> newTokens = sentence.getTokens();

      for (int i = contractionsSpan.length - 1; i >= 0; i--) {

        int start = contractionsSpan[i].getStart(), end = contractionsSpan[i]
            .getEnd();

        String lexeme = sentence.getTokens().get(start).getLexeme();
        String[] contractions = ContractionUtility.expand(lexeme);

        newTokens.remove(start);

        for (int j = contractions.length - 1; j >= 0; j--) {
          Span span = new Span(start, end);
          TokenImpl token = new TokenImpl(span, contractions[j]);
          newTokens.add(start, token);

          String caze = null;
          if (j == 0)
            caze = "B";
          else if (j == contractions.length - 1)
            caze = "E";
          else
            caze = "I";

          token.addContext(Analyzers.CONTRACTION_FINDER, caze);
        }
      }
      sentence.setTokens(newTokens);
    }
  }
}
