# Lucas Oliveira Rodrigues

- **GitHub:** @luskation
- **Curso e periodo:** Sistemas de Informacao, 4o periodo
- **Linguagem que voce domina melhor:** C++ e JavaScript
- **Ja usou Linux no dia a dia?** sim
- **Ja usou Docker?** sim
- **O que voce espera desta disciplina:** Espero aprender ao maximo e
  aprofundar meus conhecimentos em DevOps, usando o conteudo da disciplina
  como base para uma boa iniciacao cientifica e, possivelmente, para um
  mestrado no futuro.

## Diagnostico DORA do meu ultimo projeto

Pense no **ultimo projeto de software que voce entregou** — trabalho de
disciplina, projeto pessoal, estagio, TCC, o que for. Responda com honestidade.
Nao existe resposta errada aqui, e a nota **nao** depende de os numeros serem
bons.

- **Frequencia de implantacao:** quantas vezes aquele software foi para
  "producao" (entregue funcionando para alguem usar)?
  No projeto Onconutria, fizemos 4 implantacoes ate a entrega final.

- **Lead time para mudancas:** quanto tempo passava, tipicamente, entre voce
  escrever um trecho de codigo e ele estar disponivel para o usuario?
  Em torno de 40 minutos entre escrever o codigo e ele estar disponivel.

- **Tempo de restauracao:** quando algo quebrava na apresentacao ou em uso,
  quanto tempo levava para voltar a funcionar?
  Cerca de 3 horas para identificar o problema e corrigir.

- **Taxa de falha em mudancas:** que proporcao das entregas quebrou algo que
  antes funcionava?
  Aproximadamente 10% das entregas quebraram algo que funcionava antes.

### Qual metrica era a pior, e por que

A pior metrica foi o tempo de restauracao (3 horas). Mesmo com um lead time
relativamente curto (40 minutos), nao tinhamos nenhum processo de
monitoramento, rollback ou testes automatizados que ajudassem a identificar
rapidamente a causa de um problema. Quando algo quebrava, o processo era
manual e baseado em tentativa e erro, o que fazia o diagnostico demorar muito
mais do que a propria correcao.

---

> Guarde este arquivo. Na **semana 15** voce vai reler o que escreveu hoje e
> refazer o mesmo diagnostico sobre a plataforma que tera construido. A
> diferenca entre os dois textos e, na pratica, o que voce aprendeu no semestre.
