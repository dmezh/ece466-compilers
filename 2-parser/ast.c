#include "ast.h"

#include <stdio.h>
#include <stdlib.h>

#include "charutil.h"
#include "parser.tab.h"
#include "util.h"

astn* astn_alloc(enum astn_types type) {
    astn *n = safe_calloc(1, sizeof(astn));
    n->type = type;
    return n;
}

int prints = 0;

void print_ast(const astn *n) {
    static int tabs = 0;     //     -> __ <- two spaces
    for (int i=0; i<tabs; i++) printf("  ");
    if (!n) return; // if we just want to print tabs, pass NULL
    switch (n->type) {

/**/    case ASTN_NUM:
            if (n->astn_num.number.aux_type == s_CHARLIT) {
                printf("CHARLIT: '");
                emit_char(n->astn_num.number.integer);
                printf("'\n");
                break;
            } else {
                printf("CONSTANT (");
                if (!n->astn_num.number.is_signed) printf("UNSIGNED ");
                printf("%s): ", int_types_str[n->astn_num.number.aux_type]);
                if (n->astn_num.number.aux_type < s_REAL)
                    printf("%llu\n", n->astn_num.number.integer);
                else
                    printf("%Lg\n", n->astn_num.number.real);
                break;
            }

/**/    case ASTN_ASSIGN:
            printf("ASSIGNMENT\n");
            tabs++;
                print_ast(n->astn_assign.left);
                print_ast(n->astn_assign.right);
            tabs--; break;

/**/    case ASTN_IDENT:
            //printf("DBG: I ident am %p\n", (void*)n);
            printf("IDENT: %s\n", n->astn_ident.ident);
            break;

/**/    case ASTN_STRLIT:
            printf("STRING: \"");
            for (size_t i=0; i<n->astn_strlit.strlit.len; i++) {
                emit_char(n->astn_strlit.strlit.str[i]);
            }
            printf("\"\n");
            break;

/**/    case ASTN_BINOP:
            printf("BINARY OP ");
            switch (n->astn_binop.op) {
                case SHL:   printf("<<\n"); break;
                case SHR:   printf(">>\n"); break;
                case LTEQ:  printf("<=\n"); break;
                case GTEQ:  printf(">=\n"); break;
                case EQEQ:  printf("==\n"); break;
                case NOTEQ: printf("!=\n"); break;
                case LOGAND:printf("&&\n"); break;
                case LOGOR: printf("||\n"); break;
                default:    printf("%c\n", n->astn_binop.op); break;
            }
            tabs++;
                print_ast(n->astn_binop.left);
                print_ast(n->astn_binop.right);
            tabs--; break;

/**/     case ASTN_FNCALL: // wip
            printf("FNCALL w/ %d args\n", n->astn_fncall.argcount);
            astn *arg = n->astn_fncall.args;
            tabs++;
                print_ast(n->astn_fncall.fn);
                for (int i=0; i<n->astn_fncall.argcount; i++) {
                    print_ast(0); printf("ARG %d\n", i);
                    tabs++;
                        print_ast(arg->astn_list.me);
                    tabs--;
                    arg=arg->astn_list.next;
                }
            tabs--; break;

/**/    case ASTN_SELECT:
            printf("SELECT\n");
            tabs++;
                print_ast(n->astn_select.parent);
                print_ast(n->astn_select.member);
            tabs--; break;

/**/    case ASTN_UNOP:
            printf("UNOP ");
            switch (n->astn_unop.op) {
                case PLUSPLUS:      printf("POSTINC\n");                break;
                case MINUSMINUS:    printf("POSTDEC\n");                break;
                case '*':           printf("DEREF\n");                  break;
                case '&':           printf("ADDRESSOF\n");              break;
                default:            printf("%c\n", n->astn_unop.op);    break;
            }
            tabs++;
                print_ast(n->astn_unop.target);
            tabs--; break;

/**/    case ASTN_SIZEOF:
            printf("SIZEOF\n");
            tabs++;
                print_ast(n->astn_sizeof.target);
            tabs--; break;

/**/    case ASTN_TERN:
            printf("TERNARY\n");
            tabs++;
                print_ast(0); printf("IF:\n");
                tabs++; print_ast(n->astn_tern.cond); tabs--;

                print_ast(0); printf("THEN:\n");
                tabs++; print_ast(n->astn_tern.t_then); tabs--;

                print_ast(0); printf("ELSE:\n");
                tabs++; print_ast(n->astn_tern.t_else); tabs--;
            tabs--; break;

/**/    case ASTN_LIST: // unused
            print_ast(n->astn_list.me);
            break;
/**/    case ASTN_TYPESPEC:
            printf("TYPESPEC ");
            switch (n->astn_typespec.spec) {
                case TS_VOID:       printf("VOID");         break;
                case TS_CHAR:       printf("CHAR");         break;
                case TS_SHORT:      printf("SHORT");        break;
                case TS_INT:        printf("INT");          break;
                case TS_LONG:       printf("LONG");         break;
                case TS_FLOAT:      printf("FLOAT");        break;
                case TS_DOUBLE:     printf("DOUBLE");       break;
                case TS_SIGNED:     printf("SIGNED");       break;
                case TS_UNSIGNED:   printf("UNSIGNED");     break;
                case TS__BOOL:      printf("_BOOL");        break;
                case TS__COMPLEX:   printf("_COMPLEX");     break;
                default:            die("invalid typespec");
            }
            printf("\n");
            if (n->astn_typespec.next) {
                tabs++;
                    print_ast(n->astn_typespec.next);
                tabs--;
            }
            break;

/**/    case ASTN_TYPEQUAL:
            printf("TYPEQUAL ");
            switch (n->astn_typequal.qual) {
                case TQ_CONST:      printf("CONST");        break;
                case TQ_RESTRICT:   printf("RESTRICT");     break;
                case TQ_VOLATILE:   printf("VOLATILE");     break;
                default:            die("invalid typequal");
            }
            printf("\n");
            if (n->astn_typequal.next) {
                tabs++;
                    print_ast(n->astn_typequal.next);
                tabs--;
            }
            break;

/**/    case ASTN_STORSPEC:
            printf("STORAGESPEC ");
            switch (n->astn_storspec.spec) {
                case SS_EXTERN:     printf("EXTERN");       break;
                case SS_STATIC:     printf("STATIC");       break;
                case SS_AUTO:       printf("AUTO");         break;
                case SS_REGISTER:   printf("REGISTER");     break;
                default:            die("invalid storspec");
            }
            printf("\n");
            if (n->astn_storspec.next) {
                tabs++;
                    print_ast(n->astn_storspec.next);
                tabs--;
            }
            break;

/**/    case ASTN_TYPE:
            //prints++;
            //printf("DBG: I type am %p\n", (void*)n);
            //printf("%d print time %s TYPE: ", prints, n->astn_type.is_derived ? "DERIVED" : "SCALAR");
            printf("%s TYPE: ", n->astn_type.is_derived ? "DERIVED" : "SCALAR");
            if (n->astn_type.is_const) printf("CONST ");
            if (n->astn_type.is_restrict) printf("RESTRICT ");
            if (n->astn_type.is_volatile) printf("VOLATILE ");
            if (n->astn_type.is_atomic)   printf("ATOMIC ");
            if (n->astn_type.is_derived) {
                //printf("DBG: target is %p\n", (void*)n->astn_type.derived.target);
                switch (n->astn_type.derived.type) {
                    case t_PTR:     printf("PTR TO");       break;
                    case t_ARRAY:   printf("ARRAY OF");     break;
                    case t_FN:      printf("FN RETURNING"); break;
                    case t_STRUCT:  printf("STRUCT");       break;
                    case t_UNION:   printf("UNION");        break;
                    default:        die("invalid derived type");
                }
                printf("\n");
                tabs++;
                    print_ast(n->astn_type.derived.target);
                tabs--;
            } else {
                if (n->astn_type.scalar.is_unsigned) printf("UNSIGNED ");
                switch (n->astn_type.scalar.type) {
                    case t_VOID:            printf("VOID");             break;
                    case t_CHAR:            printf("CHAR");             break;
                    case t_SHORT:           printf("SHORT");            break;
                    case t_INT:             printf("INT");              break;
                    case t_LONG:            printf("LONG");             break;
                    case t_LONGLONG:        printf("LONGLONG");         break;
                    case t_BOOL:            printf("BOOL");             break;
                    case t_FLOAT:           printf("FLOAT");            break;
                    case t_DOUBLE:          printf("DOUBLE");           break;
                    case t_LONGDOUBLE:      printf("LONGDOUBLE");       break;
                    case t_FLOATCPLX:       printf("FLOATCPLX");        break;
                    case t_DOUBLECPLX:      printf("DOUBLECPLX");       break;
                    case t_LONGDOUBLECPLX:  printf("LONGDOUBLECPLX");   break;
                    default:                die("invalid scalar type");
                }
                printf("\n");
            }
            break;
        default:
            die("Unhandled AST node type");
    }
}

astn *cassign_alloc(int op, astn *left, astn *right) {
    astn *n=astn_alloc(ASTN_ASSIGN);
    n->astn_assign.left=left;
    n->astn_assign.right=binop_alloc(op, left, right);
    return n;
}

astn *binop_alloc(int op, astn *left, astn *right) {
    astn *n=astn_alloc(ASTN_BINOP);
    n->astn_binop.op=op;
    n->astn_binop.left=left;
    n->astn_binop.right=right;
    return n;
}

astn *unop_alloc(int op, astn *target) {
    astn *n=astn_alloc(ASTN_UNOP);
    n->astn_unop.op=op;
    n->astn_unop.target=target;
    return n;
}

astn *list_alloc(astn *me) {
    astn *l=astn_alloc(ASTN_LIST);
    l->astn_list.me=me;
    l->astn_list.next=NULL;
    return l;
}
//              (arg to add)(head of ll)
astn *list_append(astn* new, astn *head) {
    astn *n=list_alloc(new);
    while (head->astn_list.next) head=head->astn_list.next;
    head->astn_list.next = n;
    return n;
}

// this crime also needs to be changed
astn *qualtype_alloc(enum scalar_types t) {
    astn *n=astn_alloc(ASTN_QUALTYPE);
    n->astn_qualtype.qualtype.base_type = t;
    return n;
}

astn *typespec_alloc(enum typespec spec) {
    astn *n=astn_alloc(ASTN_TYPESPEC);
    n->astn_typespec.spec = spec;
    n->astn_typespec.next = NULL;
    return n;
}

astn *typequal_alloc(enum typequal qual) {
    astn *n=astn_alloc(ASTN_TYPEQUAL);
    n->astn_typequal.qual = qual;
    n->astn_typespec.next = NULL;
    return n;
}

astn *storspec_alloc(enum storspec spec) {
    astn *n=astn_alloc(ASTN_STORSPEC);
    n->astn_storspec.spec = spec;
    n->astn_storspec.next = NULL;
    return n;
}

astn *ptr_alloc(astn* target) {
    astn *n=astn_alloc(ASTN_TYPE);
    n->astn_type.is_derived = true;
    n->astn_type.derived.type = t_PTR;
    n->astn_type.derived.target = target;
    return n;
}

void set_ptrchain_target(astn* top, astn* target) {
    while (top->astn_type.derived.target) {
        top = top->astn_type.derived.target;
    }
    top->astn_type.derived.target = target;
}

void reset_ptrchain_target(astn* top, astn* target) {
    astn* last = top;
    while (top->astn_type.derived.target) {
        last = top;
        top = top->astn_type.derived.target;
    }
    last->astn_type.derived.target = target;
}

// get last target of chain of astn_types
astn* get_ptrchain_target(astn* top) {
    while (top->astn_type.derived.target) {
        top = top->astn_type.derived.target;
    }
    return top;
}

int list_measure(const astn *head) {
    int c = 0;
    while ((head=head->astn_list.next)) {
        c++;
    }
    return c + 1;
}
