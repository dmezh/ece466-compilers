/*
 * parser.y
 *
 * The parser!
 */

%code requires {
    #include "asmgen.h"
    #include "ast.h"
    #include "location.h"
    #include "quads.h"
    #include "semval.h"
    #include "symtab.h"
    #include "types.h"
    #include "util.h"
}

%define parse.trace

%code {
    #include <stdio.h>
    #include <stdlib.h>
    int yylex(void);
    #define ps_error(context, ...) do { \
        fprintf(stderr, "Error near %s:%d: ", context.filename, context.lineno); \
        fprintf(stderr, __VA_ARGS__); \
        fprintf(stderr, "\n"); \
        exit(-1); \
    } while(0)
    void yyerror (const char *s) { fprintf(stderr, "Parser error: %s\n", s); exit(-10); }
}

// this trash broken for the global scope, whatever
%initial-action {   YYLLOC_DEFAULT(current_scope->context, NULL, NULL);     };

%union
{
    struct number number;
    struct strlit strlit;
    char* ident;
    astn* astn_p;
    st_entry* st_entry;
}

%token INDSEL PLUSPLUS MINUSMINUS SHL SHR LTEQ GTEQ EQEQ
%token NOTEQ LOGAND LOGOR ELLIPSIS TIMESEQ DIVEQ MODEQ PLUSEQ MINUSEQ SHLEQ SHREQ ANDEQ
%token OREQ XOREQ AUTO BREAK CASE CHAR CONST CONTINUE DEFAULT DO DOUBLE ENUM EXTERN
%token FLOAT FOR GOTO INLINE INT LONG REGISTER RESTRICT RETURN SHORT SIGNED SIZEOF
%token STATIC STRUCT SWITCH TYPEDEF UNION UNSIGNED VOID VOLATILE WHILE _BOOL _COMPLEX _IMAGINARY
%token _PERISH _EXAMINE _DUMPSYMTAB IF

%nonassoc THEN
%nonassoc ELSE

%type<astn_p> statement expr expr_stmt

%token<number> NUMBER
%token<strlit> STRING
%token<ident> IDENT
%type<astn_p> primary_expr constant stringlit ident
%type<astn_p> postfix_expr array_subscript fncall arg_list select indsel postop
%type<astn_p> unary_expr unops sizeof
%type<astn_p> cast_expr
%type<astn_p> mult_expr addit_expr shift_expr
%type<astn_p> relat_expr eqlty_expr
%type<astn_p> bwand_expr bwxor_expr bwor_expr logand_expr logor_expr
%type<astn_p> tern_expr const_expr
%type<astn_p> assign

%type<astn_p> decln decln_spec init_decl_list init_decl decl direct_decl type_spec type_qual stor_spec
%type<astn_p> pointer type_qual_list direct_decl_arr arr_size

%type<astn_p> strunion_spec struct_decl_list struct_decl spec_qual_list
%type<astn_p> param_t_list param_list param_decl
%type<astn_p> struct_decltr_list struct_decltr

%type<astn_p> type_name 
%type<astn_p> abstract_decl direct_abstract_decl

%type<astn_p> block_item block_item_list compound_statement select_stmt iterat_stmt opt_expr jump_stmt labeled_stmt

%type<st_entry> external_decln fn_def

%%

done:
    translation_unit                    {   asmgen(&bb_root);     }
;

// maybe make quads here one day if you dont mind that would be good no rush
translation_unit:
    external_decln
|   translation_unit external_decln
;

external_decln:                             // kludge ish for structs/unions
    decln                               {   if($1->type == ASTN_DECL) $$=begin_st_entry($1, NS_MISC, $1->astn_decl.context);     }
|   fn_def                              {   gen_fn($1);  }
|   internal ';'                        {   $$=(st_entry*)NULL;   }
;

fn_def:
    decln_spec decl lbrace block_item_list rbrace         {  $$=st_define_function(decl_alloc($1, $2, @2), $4, @3);   }
;

// 6.8.2
compound_statement:
    lbrace { st_new_scope(SCOPE_BLOCK, @1); } block_item_list rbrace  {   $$=$3; @$=@1; st_pop_scope();  }
;

// just don't call an internal right at the start; it won't work
block_item_list:
    block_item                      {   $$=list_alloc($1);  }
|   block_item_list block_item      {   $$=list_append($2, $1); $$=$1; }
|   block_item_list internal ';'    {   $$=$1;  }
;

block_item:
    decln                       {  $$=do_decl($1);  }
|   statement
;

statement:
    expr_stmt                    {    }
|   compound_statement
|   select_stmt
|   iterat_stmt
|   jump_stmt
|   labeled_stmt
;

expr_stmt:
    expr ';'                     {   $$=$1;   }
|   semicolon                    {   $$=NULL; fprintf(stderr, "Warning: null statement near %s:%d\n", @1.filename, @1.lineno);  }
;

select_stmt:
    IF '(' expr ')' statement       %prec THEN             { $$=ifelse_alloc($3, $5, NULL); }
|   IF '(' expr ')' statement ELSE statement               { $$=ifelse_alloc($3, $5, $7); ; }
|   SWITCH '(' expr ')' statement                          { $$=astn_alloc(ASTN_SWITCH); $$->astn_switch.condition=$3; $$->astn_switch.body=$5; }
;

iterat_stmt:
    WHILE '(' expr ')' statement                                            { $$=whileloop_alloc($3, $5, false); }
|   DO statement WHILE '(' expr ')' ';'                                     { $$=whileloop_alloc($5, $2, true); }
|   FOR '(' opt_expr ';' opt_expr ';' opt_expr ')' statement                { $$=forloop_alloc($3, $5, $7, $9); }
|   FOR lparen { st_new_scope(SCOPE_BLOCK, @2); } decln { $4=do_decl($4); } opt_expr ';' opt_expr rparen statement
                                                                            { st_pop_scope(); $$=forloop_alloc($4, $6, $8, $10); }
;

jump_stmt:
    GOTO ident ';'          { $$=astn_alloc(ASTN_GOTO); $$->astn_goto.ident=$2;     }
|   CONTINUE ';'            { if (current_scope->scope_type != SCOPE_BLOCK) ps_error(@1, "fuck you"); $$=astn_alloc(ASTN_CONTINUE); }
|   BREAK ';'               { if (current_scope->scope_type != SCOPE_BLOCK) ps_error(@1, "fuck you"); $$=astn_alloc(ASTN_BREAK);    }
|   RETURN opt_expr ';'     { $$=astn_alloc(ASTN_RETURN); $$->astn_return.ret=$2;   }
;

labeled_stmt:
    ident ':' statement                 { $$=astn_alloc(ASTN_LABEL); $$->astn_label.ident=$1; $$->astn_label.statement=$3;      }
|   CASE const_expr ':' statement       { $$=astn_alloc(ASTN_CASE); $$->astn_case.case_expr=$2; $$->astn_case.statement=$4;     }
|   DEFAULT ':' statement               { $$=astn_alloc(ASTN_CASE); $$->astn_case.case_expr=NULL; $$->astn_case.statement=$3;   }
;

opt_expr:
    %empty      {   $$=NULL;    }
|   expr
;

semicolon:  ';' 
;
lbrace:     '{'
;
rbrace:     '}'
;
lparen:     '('
;
rparen:     ')'
;

// ----------------------------------------------------------------------------
// Internal actions
internal:                           // sometimes you really do want to murder the thing
    _PERISH                     {   die("You asked me to die!");    }
|   _EXAMINE ident              {   st_examine($2->astn_ident.ident);  }
|   _EXAMINE ident INDSEL ident {   st_examine_member($2->astn_ident.ident, $4->astn_ident.ident);  }
|   _DUMPSYMTAB                 {   printf("dumping current scope: "); st_dump_single();  }
;

// ----------------------------------------------------------------------------
// 6.5.1 Primary expressions
primary_expr:
    ident                       {   st_entry *e = st_lookup($1->astn_ident.ident, NS_MISC);
                                    if (!e) 
                                        ps_error(@1, "'%s' undefined", $1->astn_ident.ident);
                                    else
                                        $$=symptr_alloc(e);
                                }
|   constant
|   stringlit
|   '(' expr ')'                {   $$=$2;   }
// generic selections yeah ok
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
// ----------------------------------------------------------------------------
// 6.5.2 Postfix operators
postfix_expr:
    primary_expr
|   array_subscript
|   fncall
|   select
|   indsel
|   postop
// todo: typename+init list
;

array_subscript:
    postfix_expr '[' expr ']'   {   $$=unop_alloc('*', astn_alloc(ASTN_BINOP));
                                    $$->astn_unop.target->astn_binop.op='+';
                                    $$->astn_unop.target->astn_binop.left=$1;
                                    //astn *n = astn_alloc(ASTN_NUM);
                                    //n->astn_num.number.integer = ($3->astn_num.number.integer) * get_sizeof(descend_array($1));
                                    //n->astn_num.number.aux_type = s_INT;
                                    $$->astn_unop.target->astn_binop.right=$3;
                                }
;

fncall:
    postfix_expr '(' ')'        {   $$=astn_alloc(ASTN_FNCALL);
                                    $$->astn_fncall.fn=$1;
                                    $$->astn_fncall.argcount=0;
                                    $$->astn_fncall.args=NULL;
                                }
|   postfix_expr '('arg_list')' {   $$=astn_alloc(ASTN_FNCALL);
                                    $$->astn_fncall.fn=$1;
                                    $$->astn_fncall.args=$3;
                                    $$->astn_fncall.argcount=list_measure($$->astn_fncall.args);
                                }
;

arg_list:
    assign                      {   $$=list_alloc($1);              }
|   arg_list ',' assign         {   $$=$1; list_append($3, $1);     }
;

select:
    postfix_expr '.' ident      {   $$=astn_alloc(ASTN_SELECT);
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
// ----------------------------------------------------------------------------
// 6.5.3 Unary operators
unary_expr:
    postfix_expr
|   unops
|   PLUSPLUS unary_expr         {   astn *n=astn_alloc(ASTN_NUM);
                                    n->astn_num.number.integer=1;
                                    n->astn_num.number.is_signed=1;
                                    n->astn_num.number.aux_type=s_INT;
                                    $$=cassign_alloc('+', $2, n);
                                }
|   MINUSMINUS unary_expr       {   astn *n=astn_alloc(ASTN_NUM);
                                    n->astn_num.number.integer=1;
                                    n->astn_num.number.is_signed=1;
                                    n->astn_num.number.aux_type=s_INT;
                                    $$=cassign_alloc('-', $2, n);
                                }
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

sizeof:
    SIZEOF unary_expr           {   $$=astn_alloc(ASTN_NUM); $$->astn_num.number.integer=get_sizeof($2); 
                                    $$->astn_num.number.is_signed=false; $$->astn_num.number.aux_type=s_INT;
                                }
|   SIZEOF '(' type_name ')'    {   $$=astn_alloc(ASTN_NUM); $$->astn_num.number.integer=get_sizeof($3); 
                                    $$->astn_num.number.is_signed=false; $$->astn_num.number.aux_type=s_INT; }
;
// ----------------------------------------------------------------------------
// 6.5.4 Cast operators
cast_expr:
    unary_expr
// todo: casts
;
// ----------------------------------------------------------------------------
// 6.5.5-14 Binary (two-arg) operators
mult_expr:
    cast_expr
|   mult_expr '*' cast_expr         {   $$=binop_alloc('*', $1, $3);    }
|   mult_expr '/' cast_expr         {   $$=binop_alloc('/', $1, $3);    }
|   mult_expr '%' cast_expr         {   $$=binop_alloc('%', $1, $3);    }
;
addit_expr:
    mult_expr
|   addit_expr '+' mult_expr        {   $$=binop_alloc('+', $1, $3);    }
|   addit_expr '-' mult_expr        {   $$=binop_alloc('-', $1, $3);    }
;
shift_expr:
    addit_expr
|   shift_expr SHL addit_expr       {   $$=binop_alloc(SHL, $1, $3);    }
|   shift_expr SHR addit_expr       {   $$=binop_alloc(SHR, $1, $3);    }
;
relat_expr:
    shift_expr
|   relat_expr '<' shift_expr       {   $$=binop_alloc('<', $1, $3);    }
|   relat_expr '>' shift_expr       {   $$=binop_alloc('>', $1, $3);    }
|   relat_expr LTEQ shift_expr      {   $$=binop_alloc(LTEQ, $1, $3);   }
|   relat_expr GTEQ shift_expr      {   $$=binop_alloc(GTEQ, $1, $3);   }
;
eqlty_expr:
    relat_expr
|   eqlty_expr EQEQ relat_expr      {   $$=binop_alloc(EQEQ, $1, $3);   }
|   eqlty_expr NOTEQ relat_expr     {   $$=binop_alloc(NOTEQ, $1, $3);  }
;
bwand_expr:
    eqlty_expr
|   bwand_expr '&' eqlty_expr       {   $$=binop_alloc('&', $1, $3);    }
;
bwxor_expr:
    bwand_expr
|   bwxor_expr '^' bwand_expr       {   $$=binop_alloc('^', $1, $3);    }
;
bwor_expr:
    bwxor_expr
|   bwor_expr '|' bwxor_expr        {   $$=binop_alloc('|', $1, $3);    }
;
logand_expr:
    bwor_expr
|   logand_expr LOGAND bwor_expr    {   $$=binop_alloc(LOGAND, $1, $3); }
;
logor_expr:
    logand_expr
|   logor_expr LOGOR logand_expr    {   $$=binop_alloc(LOGOR, $1, $3);  }
;
// ----------------------------------------------------------------------------
// 6.5.15 Conditional (ternary) operator
tern_expr:
    logor_expr
|   logor_expr '?' expr ':' tern_expr   {   $$=astn_alloc(ASTN_TERN);
                                            $$->astn_tern.cond=$1;
                                            $$->astn_tern.t_then=$3;
                                            $$->astn_tern.t_else=$5;
                                        }
;
// ----------------------------------------------------------------------------
// 6.5.16 Assignment
assign:
    tern_expr
|   unary_expr '=' assign       {   $$=astn_alloc(ASTN_ASSIGN);
                                    $$->astn_assign.left=$1;
                                    $$->astn_assign.right=$3;
                                }
|   unary_expr TIMESEQ assign   {   $$=cassign_alloc('*', $1, $3);  }
|   unary_expr DIVEQ assign     {   $$=cassign_alloc('/', $1, $3);  }
|   unary_expr MODEQ assign     {   $$=cassign_alloc('%', $1, $3);  }
|   unary_expr PLUSEQ assign    {   $$=cassign_alloc('+', $1, $3);  }
|   unary_expr MINUSEQ assign   {   $$=cassign_alloc('-', $1, $3);  }
|   unary_expr SHLEQ assign     {   $$=cassign_alloc(SHL, $1, $3);  }
|   unary_expr SHREQ assign     {   $$=cassign_alloc(SHR, $1, $3);  }
|   unary_expr ANDEQ assign     {   $$=cassign_alloc('&', $1, $3);  }
|   unary_expr XOREQ assign     {   $$=cassign_alloc('^', $1, $3);  }
|   unary_expr OREQ assign      {   $$=cassign_alloc('|', $1, $3);  }
;
// ----------------------------------------------------------------------------
// 6.5.17 Comma operator
expr:
    assign
|   expr ',' assign             {   $$=binop_alloc(',', $1, $3);    }
;

// 6.6 const expr
const_expr:
    tern_expr
;

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// 6.7 Declarations
// the below needs a little logic in the first case for proper struct fwd declaration behavior
decln:
    decln_spec ';'                  { /* check for idiot user not actually declaring anything */ }
|   decln_spec init_decl_list ';'   {   $$=decl_alloc($1, $2, @$); }
// no static_assert stuff
;

// this chains them together in "reverse" order - I needed that for convenience, and it shouldn't matter
decln_spec:
    type_spec
|   type_qual
|   stor_spec
|   decln_spec type_spec            {   $$=$2; $$->astn_typespec.next = $1;     }
|   decln_spec type_qual            {   $$=$2; $$->astn_typequal.next = $1;     }
|   decln_spec stor_spec            {   $$=$2; $$->astn_storspec.next = $1;     }
;

// for now just single, but it will be easy to add the full functionality
// just make this a list and tweak begin_st_entry()
init_decl_list:
    init_decl
;

// skipping initializers at the moment!
init_decl:
    decl
|   decl '=' init                   {   fprintf(stderr, "Warning: initializer will be ignored\n");      }
;

// no initializer lists, just simple initializers
init:
    assign
;

/* 
 * A primer on how the backwards-inverted-AST fiasco is handled here -----
 * Arrays and pointers are really parsed separately from one another.
 * There isn't really a clean point where you know the ident is going to show up.
 * In addition, the type always shows up after the arrays and pointers have been
 * parsed and joined together. The type, specifiers and all, joins us in decln.
 * That's all just the grammar, not me.
 * 
 * Arrays are naturally parsed 'inside out' - child array before parent array. Easy enough
 * to deal with; we just set up each new array as the parent of the last one. Separating
 * the grammar a little into an additional direct_decl_arr helped with this.
 *
 * Pointers are also naturally parsed 'inside out', so we do the same thing as with arrays.
 * Then, all we need to do is stitch them together, with the following complication:
 *
 * The reader and I are likely in agreement that a reasonable AST representation of
 * the type of `int *i[];` looks like:
 *
 * ARRAY OF
 *   PTR TO
 *     INT
 *
 * Until the last step of the declaration (decln), the last node (INT here) is totally
 * separate from the rest of the type, and there's nothing useful at the end of the type
 * astnode chain. As such, I found it most convenient to just keep the ident as the last element 
 * in the chain, so we always know where to find it. This works nicely with the grammar.
 * When we link our PTRs with ARRAYs below, we move that last node, the IDENT, over to the child
 * chain to be its last node, so it's still last when we're done. This is in merge_dtypechains().
 * begin_st_entry() expects to find the IDENT as the very last element!
 * int **i[1][2];   // (array(1) of array(2) of ptr to ptr)
 * before: (chain of arrays)->(ident)     (chain of pointers)
 * after:  (chain of arrays)->(chain of ptrs)->(ident)
*/

// 6.7.6 Declarators
decl:                                   // similar issue with arrays was dealt with by splitting the grammar
    pointer direct_decl             {   // I could do that here instead of the if/else, but I'm dead inside
                                        if ($2->type == ASTN_TYPE && $2->astn_type.is_derived) {
                                            merge_dtypechains($2, $1);
                                            $$=$2;
                                        } else {
                                            set_dtypechain_target($1, $2);
                                            $$=$1;
                                        }
                                    }
|   direct_decl
;

// 6.7.7 Type names
// limited support

// this will be an astn_type, which may or may not be a derived type
type_name:
    spec_qual_list                 {    struct astn *n=astn_alloc(ASTN_TYPE);
                                        describe_type($1, &n->astn_type);
                                        $$=n;
                                   }
|   spec_qual_list abstract_decl   {    struct astn *n=astn_alloc(ASTN_TYPE);
                                        describe_type($1, &n->astn_type);
                                        set_dtypechain_target($2, n);
                                        $$=$2;  }
;

// will be a dertype
abstract_decl:
    pointer                        //{ printf("single ptr:\n"); print_ast($1); }
|   pointer direct_abstract_decl   { set_dtypechain_target($2, $1); $$=$2; }
|   direct_abstract_decl           //{ printf("single abstract:\n"); print_ast($1); }
;

direct_abstract_decl:
    '(' abstract_decl ')'                   { $$=$2; }
|   '[' assign ']'                          { $$=dtype_alloc(NULL, t_ARRAY); $$->astn_type.derived.size = $2;}
|   direct_abstract_decl '[' assign ']'     {   astn* n=dtype_alloc(NULL, t_ARRAY);
                                                n->astn_type.derived.size = $3;
                                                set_dtypechain_target($1, n);
                                                $$=$1;
                                            }
;

direct_decl:
    ident                           {   $$=$1;  }
|   '(' decl ')'                    {   $$=$2;  }
|   direct_decl_arr
|   direct_decl '(' param_t_list ')'{   $$=fndef_alloc($1, $3, current_scope); @$=@1;    }
|   direct_decl '(' ident_list ')'  {   ps_error(@3, "not handling K&R syntax");   }
|   direct_decl '(' ')'             {   st_new_scope(SCOPE_FUNCTION, @1); $$=fndef_alloc($1, NULL, current_scope); @$=@1;  }
;

param_t_list:
    param_list
|   param_list ',' ELLIPSIS         {  ps_error(@1, "not handling variadic fn");  }
;


param_list:
    param_decl                      {   st_new_scope(SCOPE_FUNCTION, @1);
                                        $$=declrec_alloc(begin_st_entry($1, NS_MISC, $1->astn_decl.context));
                                        $$->astn_declrec.e->is_param = true;
                                        st_reserve_stack($$->astn_declrec.e);
                                        $$=list_alloc($$);
                                    }
|   param_list ',' param_decl       {   $$=declrec_alloc(begin_st_entry($3, NS_MISC, $3->astn_decl.context));
                                        $$->astn_declrec.e->is_param = true;
                                        st_reserve_stack($$->astn_declrec.e);
                                        list_append($$, $1);
                                        $$=$1;
                                    }
;

/*
param_list:
    param_decl                      {   $$=list_alloc($1);              }
|   param_list ',' param_decl       {   list_append($3, $1); $$=$1;     }
;
*/

param_decl:
    decln_spec decl                 {   $$=decl_alloc($1, $2, @2);  }
;

// we don't care about the value because no K&R syntax
ident_list:
    ident
|   ident_list ',' ident
;

// departing from the Standard's grammar here a bit
// because of that, there is ugliness with the parenthesized decl; please un-fuck this when able
direct_decl_arr:
    ident '[' arr_size ']'              {   $$=dtype_alloc($1, t_ARRAY);
                                            $$->astn_type.derived.size = $3;
                                        }
|   direct_decl_arr '[' arr_size ']'    {   astn *n=dtype_alloc(NULL, t_ARRAY);
                                            n->astn_type.derived.size = $3;
                                            merge_dtypechains($1, n);
                                            $$=$1;
                                        }
|   '(' decl ')' '[' arr_size ']'       {   astn *n=dtype_alloc(NULL, t_ARRAY);
                                            n->astn_type.derived.size = $5;
                                            merge_dtypechains($2, n);
                                            $$=$2;
                                        }

arr_size:
    %empty                          {   $$=NULL;    }
|   assign
;

// qualifiers: yes
pointer:
    '*'                             {   $$=dtype_alloc(NULL, t_PTR);    } // root of the (potential) chain
|   '*' type_qual_list              {   $$=dtype_alloc(NULL, t_PTR);
                                        strict_qualify_type($2, &$$->astn_type);
                                    }
|   '*' pointer                     {   $$=dtype_alloc(NULL, t_PTR);
                                        set_dtypechain_target($2, $$);
                                        $$=$2;
                                    }
|   '*' type_qual_list pointer      {   $$=dtype_alloc(NULL, t_PTR);
                                        strict_qualify_type($2, &$$->astn_type);
                                        set_dtypechain_target($3, $$);
                                        $$=$3;
                                    }
;

type_qual_list:
    type_qual
|   type_qual_list type_qual        {   $$=$2;
                                        $$->astn_typequal.next = $1;
                                    }

// 6.7.1 Storage class specifiers
// no typedefs
stor_spec:
    EXTERN              {   $$=storspec_alloc(SS_EXTERN);       }
|   STATIC              {   $$=storspec_alloc(SS_STATIC);       }
|   AUTO                {   $$=storspec_alloc(SS_AUTO);         }
|   REGISTER            {   $$=storspec_alloc(SS_REGISTER);     }
;

// 6.7.2 Type specifiers
type_spec:
    VOID                {   $$=typespec_alloc(TS_VOID);         }
|   CHAR                {   $$=typespec_alloc(TS_CHAR);         }
|   SHORT               {   $$=typespec_alloc(TS_SHORT);        }
|   INT                 {   $$=typespec_alloc(TS_INT);          }
|   LONG                {   $$=typespec_alloc(TS_LONG);         }
|   FLOAT               {   $$=typespec_alloc(TS_FLOAT);        }
|   DOUBLE              {   $$=typespec_alloc(TS_DOUBLE);       }
|   SIGNED              {   $$=typespec_alloc(TS_SIGNED);       }
|   UNSIGNED            {   $$=typespec_alloc(TS_UNSIGNED);     }
|   _BOOL               {   $$=typespec_alloc(TS__BOOL);        }
|   _COMPLEX            {   $$=typespec_alloc(TS__COMPLEX);     }
|   strunion_spec       {   $$=$1;  }
;

// the struct becomes defined right after the '}' (Standard)
// note: currently forward-declares structs when it in fact should error out
// ex: struct z p; // where z has not been declared before.
// there is zero chance this is correct for all the scoping rules.
strunion_spec:
    str_or_union ident lbrace struct_decl_list rbrace   {   $$=strunion_alloc(st_define_struct($2->astn_ident.ident, $4, @2, @5, @3));  }
|   str_or_union lbrace struct_decl_list rbrace         {   ps_error(@2, "unnamed structs/unions are not yet supported");                }
|   str_or_union ident                                  {   $$=strunion_alloc(st_declare_struct($2->astn_ident.ident, false, @$));  }
;

// not an astn_p
str_or_union:
    STRUCT
;

// list of members - should this be a list of st_entry? does it even really need
// to have any semantic actions / touch the ast? I think we should synthesize a list
// of st_entry here and attempt to install them into a mini-scope symtab.

// update: made it a list of astn_decl! better not to screw around with the symtab here
// for no reason.
struct_decl_list:
    struct_decl                     {   $$=list_alloc($1);              }
|   struct_decl_list struct_decl    {   list_append($2, $1); $$=$1;     }
;

// this is equivalent 6.7 decln, where we have the specs/quals and are ready
// to install.
struct_decl:
    spec_qual_list struct_decltr_list ';'   {     $$=decl_alloc($1, $2, @$);      }
;

// this is for the members
spec_qual_list:
    type_spec
|   type_qual
|   type_spec spec_qual_list    {  $$=$1; $$->astn_typespec.next = $2;  }
|   type_qual spec_qual_list    {  $$=$1; $$->astn_typequal.next = $2;  }
;

// no ident lists at the moment
struct_decltr_list:
    struct_decltr
;

// no bitfields at the moment
struct_decltr:
    decl
;


// 6.7.3 Type qualifiers
type_qual:
    CONST               {   $$=typequal_alloc(TQ_CONST);        }
|   RESTRICT            {   $$=typequal_alloc(TQ_RESTRICT);     }
|   VOLATILE            {   $$=typequal_alloc(TQ_VOLATILE);     }
;
%%

int main() {
    yydebug = 0;
    yyparse();
}
