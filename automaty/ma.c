#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include "ma.h"

// if 'val' is null, then sets errno to 'err' and returns 'return_val'
#define CHECK_NOT_NULL(val, return_val, err)  \
    if(val == NULL){                          \
        errno = err;                          \
        return return_val;                    \
    }

#define CHECK_NOT_ZERO(val, return_val)  \
    if(val == 0){                        \
        errno = EINVAL;                  \
        return return_val;               \
    }



// returns pos-th bit from seq
static inline uint8_t get_bit(uint64_t *seq, size_t pos){
    uint64_t val = seq[pos / 64];
    return (uint8_t)(val & (1 << (pos % 64)));
}

// sets pos-th bit in seq to val
static inline void set_bit(uint64_t *seq, size_t pos, uint64_t val){
    seq[pos / 64] &= ~((uint64_t)1 << (pos % 64));
    seq[pos / 64] |= val << (pos % 64);
}


// returns the ceiling of (n / 64)
static size_t ceil_div64(size_t n){
    return n / 64 + (n % 64 != 0);
}

void * try_calloc64(size_t n){
    uint64_t *p = (uint64_t*) calloc(ceil_div64(n), sizeof(uint64_t));
    CHECK_NOT_NULL(p, NULL, ENOMEM);
    return p;
}

void * try_calloc(size_t n, size_t size){
    void *p = calloc(n, size);
    CHECK_NOT_NULL(p, NULL, ENOMEM);
    return p;
}

// identity function
static void id(uint64_t *output, uint64_t const *state, size_t m, size_t s){
    (void) s;
    memcpy(output, state, sizeof(uint64_t) * ceil_div64(m));
}


typedef struct in_bit{
    //uint8_t val; // if no automaton is connected, stores the value input
    moore_t* src_at; // source automaton
    size_t src_bit;  // from which bit of src_at take info
} in_bit;

typedef struct at_list_node at_list_node;

struct at_list_node{
    moore_t *dst_at;
    size_t dst_bit; // to which bit of dst_at's input is this output connected
    at_list_node *next;
};


// list of automatons
typedef struct at_list{
    
    at_list_node *head;
    
} at_list;


int init(at_list* list){
    list->head = (at_list_node*) try_calloc(1, sizeof(at_list_node));
    CHECK_NOT_NULL(list->head, -1, ENOMEM);
    list->head->dst_at = NULL;
    list->head->next = NULL;
    return 0;
}
    
int push(at_list* list, moore_t *at, size_t in){
    if(list->head == NULL){
        if(init(list) == -1){
            return -1;
        }
    }
    at_list_node *node = (at_list_node*) try_calloc(1, sizeof(at_list_node));
    CHECK_NOT_NULL(node, -1, ENOMEM);
    node->dst_at = at;
    node->dst_bit = in;
    node->next = list->head->next;
    list->head->next = node;
    return 0;
}    


typedef struct moore_t{
    
    size_t in_size, out_size, state_size;
    in_bit* in_bits;
    at_list* out_bits;
    uint64_t* in, *out, *state;
    transition_function_t transition_f;
    output_function_t output_f;

    
} moore_t;


 
void pop(at_list* list, moore_t *at){
    at_list_node *node = list->head;
    while(node->next->dst_at != at){
        assert(node != NULL);
        node = node->next;
    }
    at_list_node *to_delete = node->next;
    node->next = (node->next)->next;
    to_delete->dst_at->in_bits[to_delete->dst_bit].src_at = NULL;
    free(to_delete);
}

void destr(at_list* list){
    while(list->head->next != NULL) pop(list, list->head->next->dst_at);
    free(list->head);
    list->head = NULL;
}
    
static inline void fetch_input(moore_t *at){
    for(size_t i = 0; i < at->in_size; i++){
        if(at->in_bits[i].src_at == NULL) continue;
        set_bit(at->in, i, get_bit(at->in_bits[i].src_at->out,
                                   at->in_bits[i].src_bit));
    }
}

/*static inline int calc_output(moore_t *at, uint64_t const *state){
    uint64_t *new_output = (uint64_t*) try_calloc64(at->out_size);
    if(new_output == NULL) return -1;
    at->output_f(new_output, state, at->out_size, at->state_size);
    memcpy(at->out, new_output, ceil_div64(at->out_size) * sizeof(uint64_t));
    free(new_output);
}*/


moore_t * ma_create_full(size_t n, size_t m, size_t s, transition_function_t t,
                         output_function_t y, uint64_t const *q){
                             
    CHECK_NOT_ZERO(m, NULL);
    CHECK_NOT_ZERO(s, NULL);
    CHECK_NOT_NULL(t, NULL, EINVAL);
    CHECK_NOT_NULL(y, NULL, EINVAL);
    CHECK_NOT_NULL(q, NULL, EINVAL);
    
    moore_t *at = (moore_t*) malloc(sizeof(moore_t));
    //moore_t tmp = {
    at->in_size = n,
    at->in = try_calloc64(n),
    at->in_bits = (in_bit*) try_calloc(n, sizeof(in_bit)),
    at->out_size = m,
    at->out = try_calloc64(m),
    at->out_bits = (at_list*) try_calloc(m, sizeof(at_list)),
    at->state_size = s,
    at->state = try_calloc64(s),
    at->transition_f = t,
    at->output_f = y
    //};
    
    if(at->in == NULL || at->in_bits == NULL || at->out == NULL
                      || at->out_bits == NULL || at->state == NULL){
        free(at->in);
        free(at->in_bits);
        free(at->out);
        free(at->out_bits);
        free(at->state);
        free(at);
        return NULL;
    }
    
    //memcpy(at, &tmp, sizeof(moore_t));
        
    at->output_f(at->out, q, at->out_size, at->state_size);
    memcpy(at->state, q, sizeof(uint64_t) * ceil_div64(s));
    return at;
}
                         
                         
moore_t * ma_create_simple(size_t n, size_t m, transition_function_t t){
    uint64_t *q = try_calloc64(m);
    if(q == NULL) return NULL;
    moore_t *at = ma_create_full(n, m, m, t, &id, q);
    free(q);
    return at;
}


void ma_delete(moore_t *a){
    if(a == NULL) return;
    ma_disconnect(a, 0, a->in_size);
    
    for(size_t i = 0; i < a->out_size; i++){
        destr(&(a->out_bits[i]));
    }
    
    free(a);
}


int ma_connect(moore_t *a_in, size_t in, moore_t *a_out, size_t out, size_t num){
    
    CHECK_NOT_NULL(a_in, -1, EINVAL);
    CHECK_NOT_NULL(a_out, -1, EINVAL);
    CHECK_NOT_ZERO(num, -1);
    if(in + num > a_in->in_size || out + num > a_out->out_size){
        errno = EINVAL;
        return -1;
    } 
    
    in_bit *old_input = (in_bit*) try_calloc64(a_in->in_size);
    CHECK_NOT_NULL(old_input, -1, ENOMEM);
    memcpy(old_input, a_in->in_bits,
           ceil_div64(a_in->in_size) * sizeof(uint64_t));
    
    if(ma_disconnect(a_in, in, num) != 0){
        memcpy(a_in->in_bits, old_input,
               ceil_div64(a_in->in_size) * sizeof(uint64_t));
        free(old_input);
        return -1;
    }
    
    
    for(size_t i = 0; i < num; i++){
        a_in->in_bits[in + i] = (in_bit) {
            .src_at = a_out,
            .src_bit = out + i
        };
        if(push(&(a_out->out_bits[out + i]), a_in, in + i) == -1){
            for(size_t j = 0; j < i; j++){
                pop(&(a_out->out_bits[out + j]), a_in);
            }
            memcpy(a_in->in_bits, old_input,
                   ceil_div64(a_in->in_size) * sizeof(uint64_t));
            free(old_input);
            return -1;
        }
    }
    
    return 0;    
}


int ma_disconnect(moore_t *a_in, size_t in, size_t num){
    
    CHECK_NOT_NULL(a_in, -1, EINVAL);
    CHECK_NOT_ZERO(num, -1);
    if(in + num > a_in->in_size){
        errno = EINVAL;
        return -1;
    }
    
    moore_t *src;
    for(size_t i = in; i < in + num; i++){
        src = a_in->in_bits[i].src_at;
        if(src == NULL) continue;
        pop(&(src->out_bits[a_in->in_bits[i].src_bit]), src);
    }
    
    return 0;
}


int ma_set_input(moore_t *a, uint64_t const *input){
    
    CHECK_NOT_NULL(a, -1, EINVAL);
    CHECK_NOT_ZERO(a->in_size, -1);
    CHECK_NOT_NULL(input, -1, EINVAL);
    
    uint64_t *input_copy = (uint64_t*) try_calloc64(a->in_size);
    if(input_copy == NULL) return -1;
    
    for(size_t i = 0; i < a->in_size; i++){
        if(a->in_bits[i].src_at == NULL){
            set_bit(a->in, i, get_bit(input_copy, i));
        }
    }
    free(input_copy);
    
    return 0;
}


int ma_set_state(moore_t *a, uint64_t const *state){
    CHECK_NOT_NULL(a, -1, EINVAL);
    CHECK_NOT_NULL(state, -1, EINVAL);
    
    //if(calc_output(a, state) == -1) return -1;
    a->output_f(a->out, state, a->out_size, a->state_size);
    memcpy(a->state, state, ceil_div64(a->state_size) * sizeof(uint64_t));
    
    return 0;
}


uint64_t const * ma_get_output(moore_t const *a){
    CHECK_NOT_NULL(a, NULL, EINVAL);
    return a->out;
}


int ma_step(moore_t *at[], size_t num){
    CHECK_NOT_NULL(at, -1, EINVAL);
    CHECK_NOT_ZERO(num, -1);
    
    for(size_t i = 0; i < num; i++){
        CHECK_NOT_NULL(at[i], -1, EINVAL);
        fetch_input(at[i]);
    }
    
    for(size_t i = 0; i < num; i++){
        at[i]->transition_f(at[i]->state, at[i]->in, at[i]->state,
                           at[i]->in_size, at[i]->state_size);
        at[i]->output_f(at[i]->out, at[i]->state,
                       at[i]->out_size, at[i]->state_size);
    }
    
    return 0;
}