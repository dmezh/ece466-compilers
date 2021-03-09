/* parser */

%{
    #include <stdio.h>
    #include "semval.h"
    #include "ast.h"
    int yylex(void);
    void yyerror (const char *s) { fprintf(stderr, "o! %s\n", s);}
    astn *unop_alloc(int op, astn* target);
%}

%define parse.trace

%union
{
    struct number number;
    struct strlit strlit;
    unsigned char charlit;
    char* ident;
    astn* astn_p;
}

%token INDSEL PLUSPLUS MINUSMINUS SHL SHR LTEQ GTEQ EQEQ
%token NOTEQ LOGAND LOGOR ELLIPSIS TIMESEQ DIVEQ MODEQ PLUSEQ MINUSEQ SHLEQ SHREQ ANDEQ
%token OREQ XOREQ AUTO BREAK CASE CHAR CONST CONTINUE DEFAULT DO DOUBLE ELSE ENUM EXTERN
%token FLOAT FOR GOTO IF INLINE INT LONG REGISTER RESTRICT RETURN SHORT SIGNED SIZEOF
%token STATIC STRUCT SWITCH TYPEDEF UNION UNSIGNED VOID VOLATILE WHILE _BOOL _COMPLEX _IMAGINARY

%token<number> NUMBER
%token<strlit> STRING
%token<charlit> CHARLIT
%token<ident> IDENT
%type<astn_p> constant
%type<astn_p> ident
%type<astn_p> stringlit
%type<astn_p> statement
%type<astn_p> expr
%type<astn_p> array_subscript
%type<astn_p> fncall
%type<astn_p> select
%type<astn_p> indsel
%type<astn_p> postop
%type<astn_p> primary_expr
%type<astn_p> postfix_expr
%type<astn_p> unary_expr
%type<astn_p> sizeof
%type<astn_p> cast_expr
%type<astn_p> unops

%left '.'
%left PLUSPLUS MINUSMINUS
%%

statement:
    expr ';'                    {   $$=$1; print_ast($1); YYACCEPT; }
;

expr:
    cast_expr
;

// 6.5.1 Primary expressions
primary_expr:
    ident
|   constant
|   stringlit
|   '(' expr ')'                {   $$=$2;   }
// the fuck is a generic selection?
;

// 6.5.2 Postfix operators
postfix_expr:
    primary_expr
|   array_subscript
|   fncall
|   select
|   indsel
|   postop
// todo: ++, --, typename+init list
;

unary_expr:
    postfix_expr
|   unops
// todo: pre ++ and --
// todo: casts
|   sizeof
;

unops:
    '&' cast_expr               {   $$=unop_alloc('&', $2); }
|   '*' cast_expr               {   $$=unop_alloc('*', $2); }
|   '+' cast_expr               {   $$=unop_alloc('+', $2); }
|   '-' cast_expr               {   $$=unop_alloc('-', $2); }
|   '!' cast_expr               {   $$=unop_alloc('!', $2); }
|   '~' cast_expr               {   $$=unop_alloc('~', $2); }
;

cast_expr:
    unary_expr
;

sizeof:
    SIZEOF unary_expr           {   $$=astn_alloc(ASTN_SIZEOF);
                                    $$->astn_sizeof.target=$2;
                                }
// todo: sizeof abstract types
;

array_subscript:
    postfix_expr '[' expr ']'   {   $$=unop_alloc('*', astn_alloc(ASTN_BINOP));
                                    $$->astn_unop.target->astn_binop.op='+';
                                    $$->astn_unop.target->astn_binop.left=$1;
                                    $$->astn_unop.target->astn_binop.right=$3;
                                }
;

fncall:
    postfix_expr '(' ')'        {   $$=astn_alloc(ASTN_FNCALL);
                                    $$->astn_fncall.fn=$1;
                                    $$->astn_fncall.args=NULL;
                                }
    // todo: with args
;

select:
    postfix_expr '.' ident      {
                                    $$=astn_alloc(ASTN_SELECT);
                                    $$->astn_select.parent = $1;
                                    $$->astn_select.member = $3;
                                }
;

indsel:
    postfix_expr INDSEL ident   {   $$=astn_alloc(ASTN_SELECT);
                                    $$->astn_select.parent=unop_alloc('*', $1);
                                    $$->astn_select.member=$3;
                                }
;

postop:
    postfix_expr MINUSMINUS     {   $$=unop_alloc(MINUSMINUS, $1);  }
|   postfix_expr PLUSPLUS       {   $$=unop_alloc(PLUSPLUS, $1);    }
;

ident:
    IDENT                       {   $$=astn_alloc(ASTN_IDENT);
                                    $$->astn_ident.ident=$1;
                                }
;

constant:
    NUMBER                      {   $$=astn_alloc(ASTN_NUM);
                                    $$->astn_num.number=$1;
                                }
;

stringlit:
    STRING                      {   $$=astn_alloc(ASTN_STRLIT);
                                    $$->astn_strlit.strlit=$1;
                                }
;   

%%

astn *unop_alloc(int op, astn* target) {
    astn *n=astn_alloc(ASTN_UNOP);
    n->astn_unop.op=op;
    n->astn_unop.target=target;
    return n;
}

int main() {
    yydebug = 0;
    yyparse();
}