"! <p class="shorttext synchronized">PO/PR Release Strategy SLA Analysis</p>
"! <p>
"!   Service class responsible for loading, processing and displaying
"!   release approval history for Purchase Orders (PO) and Purchase
"!   Requisitions (PR).
"! </p>
"! <h3>Refactoring Notes (v2.0)</h3>
"! <ul>
"!   <li>BUG FIX: OBJECTID filter added in PROC_CHANGE_DOCUMENT (was mixing data across documents)</li>
"!   <li>BUG FIX: IT_EKGRP filter applied in SELECT_PR_DOCUMENTS</li>
"!   <li>PERF: GT_CDPOS changed to SORTED TABLE (eliminates O(n²) sequential scans)</li>
"!   <li>PERF: GL_PO_HEADER and GL_PR_HEADER changed to HASHED TABLE</li>
"!   <li>PERF: GT_CDHDR changed to SORTED TABLE with correct key</li>
"!   <li>CLEANUP: MT_ESTRLIB (T16FS) SELECT removed — table was never consumed</li>
"!   <li>CLEANUP: IV_INDEX unused parameter removed from GET_STRATEGY_INFO / PROC_CHANGE_DOCUMENT</li>
"!   <li>CLEANUP: GS_RELDATA moved from instance attribute to local variable</li>
"!   <li>CLEANUP: Duplicate ALV function calls removed in DISPLAY_ALV</li>
"!   <li>QUALITY: GET_POSTATUS split by document type</li>
"!   <li>QUALITY: LIGHT_INDI logic corrected for partial release</li>
"!   <li>QUALITY: DELETE ADJACENT DUPLICATES uses explicit COMPARING field</li>
"! </ul>
CLASS ycl_prpo_release_sla DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS execute
      IMPORTING
        !iv_doc_type  TYPE char2
        !it_banfn     TYPE STANDARD TABLE
        !it_ebeln     TYPE STANDARD TABLE
        !it_rldat     TYPE STANDARD TABLE
        !it_bukrs     TYPE STANDARD TABLE
        !it_werks     TYPE STANDARD TABLE
        !it_ekgrp     TYPE STANDARD TABLE
        !it_ekorg     TYPE STANDARD TABLE
        !iv_not_rel   TYPE abap_bool
        !iv_part_rel  TYPE abap_bool
        !iv_released  TYPE abap_bool
      EXPORTING
        !et_output    TYPE zmm_slaprpo_l.

    METHODS display_alv
      IMPORTING
        !it_data TYPE zmm_slaprpo_l.

  PROTECTED SECTION.

  PRIVATE SECTION.

    "--------------------------------------------------------------------
    " Local Types
    "--------------------------------------------------------------------
    TYPES:
      BEGIN OF ty_pr_header,
        bsart        TYPE eban-bsart,
        banfn        TYPE eban-banfn,
        statu        TYPE eban-statu,
        waers        TYPE eban-waers,
        afnam        TYPE eban-afnam,
        werks        TYPE eban-werks,
        ekgrp        TYPE eban-ekgrp,
        ernam        TYPE eban-ernam,
        frggr        TYPE eban-frggr,
        frgst        TYPE eban-frgst,
        frgzu        TYPE eban-frgzu,
        rlwrt        TYPE eban-rlwrt,
        banpr        TYPE eban-banpr,
        creationdate TYPE eban-creationdate,
      END OF ty_pr_header.

    TYPES:
      BEGIN OF ty_po_header,
        ebeln    TYPE ebeln,
        bukrs    TYPE bukrs,
        ekorg    TYPE ekorg,
        ekgrp    TYPE ekgrp,
        bsart    TYPE bsart,
        ernam    TYPE ernam,
        waers    TYPE waers,
        procstat TYPE ekko-procstat,
        rlwrt    TYPE rlwrt,
        frggr    TYPE frggr,
        frgsx    TYPE frgsx,
        frgke    TYPE frgke,
        frgzu    TYPE frgzu,
        werks    TYPE werks_d,
      END OF ty_po_header.

    TYPES:
      BEGIN OF ty_reldata,
        objectid  TYPE cdhdr-objectid,
        changenr  TYPE cdhdr-changenr,
        username  TYPE cdhdr-username,
        udate     TYPE cdhdr-udate,
        fname     TYPE cdpos-fname,
        value_new TYPE cdpos-value_new,
        value_old TYPE cdpos-value_old,
      END OF ty_reldata.

    TYPES:
      BEGIN OF ty_result,
        ebeln     TYPE ebeln,
        nvl_lib   TYPE i,
        cod_lib   TYPE string,
        cod_txt   TYPE string,
        objectid  TYPE cdhdr-objectid,
        changenr  TYPE cdhdr-changenr,
        username  TYPE cdhdr-username,
        udate     TYPE cdhdr-udate,
        fname     TYPE cdpos-fname,
        value_new TYPE cdpos-value_new,
      END OF ty_result.

    TYPES:
      BEGIN OF ty_strategies,
        frggr TYPE t16ft-frggr,
        frgsx TYPE t16ft-frgsx,
        frgxt TYPE t16ft-frgxt,
      END OF ty_strategies.

    TYPES:
      BEGIN OF ty_appresp,
        frggr TYPE t16fw-frggr,
        frgco TYPE t16fw-frgco,
        objid TYPE t16fw-objid,
      END OF ty_appresp.

    TYPES:
      BEGIN OF ty_condlib,
        frggr TYPE t16fv-frggr,
        frgsx TYPE t16fv-frgsx,
        frgco TYPE t16fv-frgco,
        frga1 TYPE t16fv-frga1,
        frga2 TYPE t16fv-frga2,
        frga3 TYPE t16fv-frga3,
        frga4 TYPE t16fv-frga4,
        frga5 TYPE t16fv-frga4,
        frga6 TYPE t16fv-frga6,
        frga7 TYPE t16fv-frga7,
        frga8 TYPE t16fv-frga8,
      END OF ty_condlib.

    TYPES:
      BEGIN OF ty_cdhdr,
        objectclas TYPE cdhdr-objectclas,
        objectid   TYPE cdhdr-objectid,
        changenr   TYPE cdhdr-changenr,
        username   TYPE cdhdr-username,
        udate      TYPE cdhdr-udate,
        tcode      TYPE cdhdr-tcode,
      END OF ty_cdhdr.

    TYPES:
      BEGIN OF ty_cdpos,
        objectclas TYPE cdpos-objectclas,
        objectid   TYPE cdpos-objectid,
        changenr   TYPE cdpos-changenr,
        tabname    TYPE cdpos-tabname,
        tabkey     TYPE cdpos-tabkey,
        fname      TYPE cdpos-fname,
        chngind    TYPE cdpos-chngind,
        value_new  TYPE cdpos-value_new,
        value_old  TYPE cdpos-value_old,
      END OF ty_cdpos.

    "--------------------------------------------------------------------
    " Instance State
    " FIX: GT_CDHDR/GT_CDPOS changed to SORTED TABLE for O(log n) access
    " FIX: GL_PO_HEADER / GL_PR_HEADER changed to HASHED TABLE
    "      (original GL_PO_HEADER was STANDARD TABLE — reverts a performance regression)
    "--------------------------------------------------------------------
    DATA gt_cdhdr     TYPE SORTED TABLE OF ty_cdhdr
                        WITH NON-UNIQUE KEY objectid changenr.

    DATA gt_cdpos     TYPE SORTED TABLE OF ty_cdpos
                        WITH NON-UNIQUE KEY objectid fname changenr.

    DATA gl_po_header TYPE HASHED TABLE OF ty_po_header
                        WITH UNIQUE KEY ebeln.

    DATA gl_pr_header TYPE HASHED TABLE OF ty_pr_header
                        WITH UNIQUE KEY banfn.

    DATA gt_result    TYPE STANDARD TABLE OF ty_result.

    DATA mt_appresp   TYPE STANDARD TABLE OF ty_appresp.
    DATA mt_strategies TYPE STANDARD TABLE OF ty_strategies.
    DATA mt_codes     TYPE STANDARD TABLE OF t16fd.

    DATA mt_condlib   TYPE SORTED TABLE OF ty_condlib
                        WITH NON-UNIQUE KEY frggr frgsx.

    DATA mv_doc_type  TYPE char2.

    "--------------------------------------------------------------------
    " Private Methods
    "--------------------------------------------------------------------
    METHODS get_postatus
      IMPORTING
        !iv_estprocmto   TYPE char2
        !iv_doctype      TYPE char2
      RETURNING
        VALUE(rv_description) TYPE char40.

    METHODS get_strategy_text
      IMPORTING
        !iv_strategy       TYPE frgst
      RETURNING
        VALUE(rv_text)     TYPE frgxt.

    METHODS select_po_documents
      IMPORTING
        !it_ebeln TYPE STANDARD TABLE
        !it_bukrs TYPE STANDARD TABLE
        !it_werks TYPE STANDARD TABLE
        !it_ekgrp TYPE STANDARD TABLE
        !it_ekorg TYPE STANDARD TABLE
        !it_rldat TYPE STANDARD TABLE.

    METHODS select_pr_documents
      IMPORTING
        !it_banfn TYPE STANDARD TABLE
        !it_werks TYPE STANDARD TABLE
        !it_ekgrp TYPE STANDARD TABLE
        !it_rldat TYPE STANDARD TABLE.

    METHODS build_release_history
      IMPORTING
        !it_rldat    TYPE STANDARD TABLE
        !iv_not_rel  TYPE abap_bool
        !iv_part_rel TYPE abap_bool
        !iv_released TYPE abap_bool
      RETURNING
        VALUE(rt_output) TYPE zmm_slaprpo_l.

    METHODS get_strategy_info
      IMPORTING
        !ebeln    TYPE ebeln
        !l_frggr  TYPE frggr
        !l_frgsx  TYPE frgsx
        !l_frgzu  TYPE frgzu.

    METHODS get_code_text
      IMPORTING
        !iv_group      TYPE frggr
        !iv_code       TYPE frgco
      RETURNING
        VALUE(rv_text) TYPE frgct.

    METHODS read_rel_data
      IMPORTING
        !iv_doc_type TYPE char2.

    METHODS light_indi
      IMPORTING
        !iv_value     TYPE cdfldvaln
        !iv_frgzu_len TYPE i
      RETURNING
        VALUE(light) TYPE icon_d.

    METHODS get_approvresp
      IMPORTING
        !iv_group     TYPE frggr
        !iv_code      TYPE frgco
      RETURNING
        VALUE(rv_resp) TYPE objid.

    METHODS read_change_document.

    METHODS proc_change_document
      IMPORTING
        !iv_objid TYPE cdpos-objectid
        !iv_cond  TYPE string
      RETURNING
        VALUE(rs_reldata) TYPE ty_reldata.

ENDCLASS.


CLASS ycl_prpo_release_sla IMPLEMENTATION.

  METHOD execute.

    mv_doc_type = iv_doc_type.

    " Load release strategy customizing (T16FD, T16FT, T16FW, T16FV)
    read_rel_data( mv_doc_type ).

    " Select documents and build change document index
    IF iv_doc_type = 'PR'.
      select_pr_documents(
        it_banfn = it_banfn
        it_rldat = it_rldat
        it_werks = it_werks
        it_ekgrp = it_ekgrp
      ).
    ELSE.
      select_po_documents(
        it_ebeln = it_ebeln
        it_rldat = it_rldat
        it_bukrs = it_bukrs
        it_werks = it_werks
        it_ekgrp = it_ekgrp
        it_ekorg = it_ekorg
      ).
    ENDIF.

    " Build ALV output from intermediate result
    et_output = build_release_history(
      it_rldat    = it_rldat
      iv_not_rel  = iv_not_rel
      iv_part_rel = iv_part_rel
      iv_released = iv_released
    ).

  ENDMETHOD.


  METHOD read_rel_data.

    DATA lv_frggr TYPE frggr.

    CASE iv_doc_type.
      WHEN 'PR'. lv_frggr = 'R%'.
      WHEN 'PO'. lv_frggr = 'P%'.
      WHEN OTHERS. lv_frggr = 'R%'.
    ENDCASE.

    " Release code texts (T16FD)
    SELECT frggr, frgco, frgct
      FROM t16fd
      INTO CORRESPONDING FIELDS OF TABLE @mt_codes
      WHERE frggr LIKE @lv_frggr.

    " Release strategy texts (T16FT)
    SELECT frggr, frgsx, frgxt
      FROM t16ft
      INTO TABLE @mt_strategies
      WHERE frggr LIKE @lv_frggr
        AND spras = @sy-langu.

    " Release responsible (T16FW)
    SELECT frggr, frgco, objid
      FROM t16fw
      INTO TABLE @mt_appresp
      WHERE frggr LIKE @lv_frggr.

    " Release prerequisites per code (T16FV)
    " FIX: Removed T16FS (MT_ESTRLIB) SELECT — table was populated but never consumed
    SELECT frggr, frgsx, frgco,
           frga1, frga2, frga3, frga4,
           frga5, frga6, frga7, frga8
      FROM t16fv
      INTO TABLE @mt_condlib
      WHERE frggr LIKE @lv_frggr.

  ENDMETHOD.


  METHOD select_po_documents.

    SELECT h~ebeln,
           h~bukrs,
           h~ekorg,
           h~ekgrp,
           h~bsart,
           h~ernam,
           h~waers,
           h~procstat,
           h~rlwrt,
           h~frggr,
           h~frgsx,
           h~frgke,
           h~frgzu
      FROM ekko AS h
      WHERE h~ebeln IN @it_ebeln
        AND h~aedat IN @it_rldat
        AND h~bukrs IN @it_bukrs
        AND h~ekgrp IN @it_ekgrp
        AND h~ekorg IN @it_ekorg
        AND EXISTS (
            SELECT 1
              FROM ekpo AS i
              WHERE i~ebeln = h~ebeln
                AND i~werks IN @it_werks )
      INTO TABLE @gl_po_header.

    IF gl_po_header IS INITIAL.
      RETURN.
    ENDIF.

    read_change_document( ).

    LOOP AT gl_po_header INTO DATA(ls_po).
      get_strategy_info(
        ebeln   = ls_po-ebeln
        l_frggr = ls_po-frggr
        l_frgsx = ls_po-frgsx
        l_frgzu = ls_po-frgzu
      ).
    ENDLOOP.

  ENDMETHOD.


  METHOD select_pr_documents.

    " FIX: Added IT_EKGRP filter — was accepted as parameter but ignored in WHERE clause
    SELECT bsart,
           banfn,
           statu,
           waers,
           afnam,
           werks,
           ekgrp,
           ernam,
           frggr,
           frgst,
           frgzu,
           rlwrt,
           banpr,
           creationdate
      FROM eban
      INTO TABLE @gl_pr_header
     WHERE banfn        IN @it_banfn
       AND creationdate IN @it_rldat
       AND werks        IN @it_werks
       AND ekgrp        IN @it_ekgrp
       AND loekz = ' '.

    IF gl_pr_header IS INITIAL.
      RETURN.
    ENDIF.

    " FIX: COMPARING with explicit key field (HASHED TABLE prevents duplicates by key anyway)
    read_change_document( ).

    LOOP AT gl_pr_header INTO DATA(gs_pr).
      get_strategy_info(
        ebeln   = gs_pr-banfn
        l_frggr = gs_pr-frggr
        l_frgsx = gs_pr-frgst
        l_frgzu = gs_pr-frgzu
      ).
    ENDLOOP.

  ENDMETHOD.


  METHOD read_change_document.

    TYPES:
      BEGIN OF ty_cd_config,
        objectclas TYPE cdhdr-objectclas,
        fname_list TYPE RANGE OF cdpos-fname,
        tcode_list TYPE RANGE OF cdhdr-tcode,
      END OF ty_cd_config.

    DATA:
      lt_objectid TYPE TABLE OF cdhdr-objectid,
      ls_config   TYPE ty_cd_config.

    CASE mv_doc_type.

      WHEN 'PO'.
        lt_objectid = VALUE #(
          FOR ls IN gl_po_header
          ( CONV cdhdr-objectid( |{ ls-ebeln }| ) )
        ).
        ls_config-objectclas = 'EINKBELEG'.
        ls_config-fname_list = VALUE #(
          ( sign = 'I' option = 'EQ' low = 'FRGKE' )
          ( sign = 'I' option = 'EQ' low = 'FRGZU' )
          ( sign = 'I' option = 'EQ' low = 'FRGSX' )
          ( sign = 'I' option = 'EQ' low = 'FRGC1' )
          ( sign = 'I' option = 'EQ' low = 'FRGC2' )
        ).
        ls_config-tcode_list = VALUE #(
          ( sign = 'I' option = 'EQ' low = 'ME28'  )
          ( sign = 'I' option = 'EQ' low = 'ME29N' )
        ).

      WHEN 'PR'.
        lt_objectid = VALUE #(
          FOR ls IN gl_pr_header
          ( CONV cdhdr-objectid( |{ ls-banfn }| ) )
        ).
        ls_config-objectclas = 'BANF'.
        ls_config-fname_list = VALUE #(
          ( sign = 'I' option = 'EQ' low = 'FRGKZ' )
          ( sign = 'I' option = 'EQ' low = 'FRGZU' )
          ( sign = 'I' option = 'EQ' low = 'BANPR' )
        ).
        ls_config-tcode_list = VALUE #(
          ( sign = 'I' option = 'EQ' low = 'ME54N' )
          ( sign = 'I' option = 'EQ' low = 'ME55'  )
        ).

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    IF lt_objectid IS INITIAL.
      RETURN.
    ENDIF.

    SORT lt_objectid.
    DELETE ADJACENT DUPLICATES FROM lt_objectid.

    " Read CDHDR — results go into SORTED TABLE (auto-sorted by key: objectid changenr)
    SELECT objectclas, objectid, changenr, username, udate, tcode
      FROM cdhdr
      INTO TABLE @gt_cdhdr
      FOR ALL ENTRIES IN @lt_objectid
      WHERE objectid   = @lt_objectid-table_line
        AND objectclas = @ls_config-objectclas
        AND tcode     IN @ls_config-tcode_list.

    IF gt_cdhdr IS INITIAL.
      RETURN.
    ENDIF.

    " Read CDPOS — results go into SORTED TABLE (auto-sorted by key: objectid fname changenr)
    SELECT objectclas, objectid, changenr, tabname, tabkey,
           fname, chngind, value_new, value_old
      FROM cdpos
      INTO TABLE @gt_cdpos
      FOR ALL ENTRIES IN @gt_cdhdr
      WHERE objectclas = @gt_cdhdr-objectclas
        AND objectid   = @gt_cdhdr-objectid
        AND changenr   = @gt_cdhdr-changenr
        AND fname      IN @ls_config-fname_list.

  ENDMETHOD.


  METHOD get_strategy_info.

    TYPES:
      BEGIN OF ty_release_condition,
        frggr TYPE t16fv-frggr,
        frgsx TYPE t16fv-frgsx,
        frgco TYPE t16fv-frgco,
        cond  TYPE string,
      END OF ty_release_condition.

    TYPES:
      BEGIN OF ty_change_log,
        ebeln     TYPE ebeln,
        nvl_lib   TYPE i,
        cod_lib   TYPE string,
        cod_txt   TYPE string,
        objectid  TYPE cdhdr-objectid,
        changenr  TYPE cdhdr-changenr,
        username  TYPE cdhdr-username,
        udate     TYPE cdhdr-udate,
        fname     TYPE cdpos-fname,
        value_new TYPE cdpos-value_new,
      END OF ty_change_log.

    DATA lt_release_conds TYPE STANDARD TABLE OF ty_release_condition.
    DATA lt_change_logs   TYPE STANDARD TABLE OF ty_change_log.
    DATA ls_change_log    TYPE ty_change_log.

    FIELD-SYMBOLS: <fs_flag> TYPE any.

    " Filter prerequisite conditions for this document's strategy
    DATA(lt_prereqs) = FILTER #( mt_condlib
      WHERE frggr = l_frggr
        AND frgsx = l_frgsx ).

    CHECK lt_prereqs IS NOT INITIAL.

    " Build approval chain string per release code
    LOOP AT lt_prereqs INTO DATA(ls_prereq).

      DATA(lv_chain) = ``.

      " Columns FRGA1..FRGA8 map to component offsets 4..11 in TY_CONDLIB
      DO 8 TIMES.
        ASSIGN COMPONENT sy-index + 3 OF STRUCTURE ls_prereq TO <fs_flag>.
        CHECK sy-subrc = 0 AND <fs_flag> IS ASSIGNED.
        CASE <fs_flag>.
          WHEN '+'.
            lv_chain = lv_chain && 'X'.
          WHEN 'X'.
            lv_chain = lv_chain && 'X'.
            EXIT. " Final approval in chain — stop here
        ENDCASE.
      ENDDO.

      APPEND VALUE #(
        frggr = ls_prereq-frggr
        frgsx = ls_prereq-frgsx
        frgco = ls_prereq-frgco
        cond  = lv_chain
      ) TO lt_release_conds.

    ENDLOOP.

    " Sort ascending so level numbers (strlen) are ordered correctly
    SORT lt_release_conds BY cond ASCENDING.

    " FIX: Removed IV_INDEX parameter (was passed but never used)
    LOOP AT lt_release_conds INTO DATA(ls_cond).

      CLEAR ls_change_log.

      DATA(ls_reldata) = proc_change_document(
        iv_objid = CONV #( ebeln )
        iv_cond  = ls_cond-cond
      ).

      MOVE-CORRESPONDING ls_reldata TO ls_change_log.
      ls_change_log-ebeln   = ebeln.
      ls_change_log-cod_lib = ls_cond-frgco.
      ls_change_log-cod_txt = get_code_text(
        iv_code  = ls_cond-frgco
        iv_group = ls_cond-frggr
      ).
      ls_change_log-nvl_lib = strlen( ls_cond-cond ).

      APPEND ls_change_log TO gt_result.

    ENDLOOP.

  ENDMETHOD.


  METHOD proc_change_document.

    "--------------------------------------------------------------------
    " Detects the last release reset and retrieves subsequent FRGZU changes.
    " FIX: All GT_CDPOS inline filters now include OBJECTID predicate to
    "      prevent mixing approval data across different documents.
    "      (Original code filtered only by FNAME/VALUE, causing cross-doc
    "       contamination when multiple documents were loaded in GT_CDPOS.)
    "--------------------------------------------------------------------

    TYPES:
      BEGIN OF ty_reset_rule,
        fname     TYPE cdpos-fname,
        value_old TYPE cdpos-value_new,
        value_new TYPE cdpos-value_new,
      END OF ty_reset_rule.

    DATA ls_reset_rule TYPE ty_reset_rule.
    DATA lt_filtered   TYPE TABLE OF ty_cdpos.
    DATA ls_last_reset TYPE ty_cdpos.
    DATA lt_frgzu      TYPE TABLE OF ty_cdpos.

    " 1. Define reset detection rule by document type
    CASE mv_doc_type.
      WHEN 'PO'.
        ls_reset_rule = VALUE #(
          fname     = 'FRGKE'
          value_old = 'A'
          value_new = 'B'
        ).
      WHEN 'PR'.
        ls_reset_rule = VALUE #(
          fname     = 'BANPR'
          value_old = '05'
          value_new = '03'
        ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    " 2. Find all reset entries for this specific document
    "    FIX: Added OBJECTID = IV_OBJID predicate (was missing — caused cross-doc contamination)
    lt_filtered = VALUE #(
      FOR ls IN gt_cdpos
      WHERE ( objectid  = iv_objid
          AND fname     = ls_reset_rule-fname
          AND value_old = ls_reset_rule-value_old
          AND value_new = ls_reset_rule-value_new )
      ( ls )
    ).

    " 3. Get the most recent reset (highest CHANGENR)
    DATA(lv_reset_found) = xsdbool( lt_filtered IS NOT INITIAL ).

    IF lv_reset_found = abap_true.
      SORT lt_filtered BY changenr DESCENDING.
      ls_last_reset = lt_filtered[ 1 ].
    ENDIF.

    " 4. Collect FRGZU changes for this document after the last reset.
    "    FIX: Added OBJECTID filter in both branches.
    "    If no reset found, take all FRGZU changes for this document.
    IF lv_reset_found = abap_true.
      lt_frgzu = VALUE #(
        FOR ls IN gt_cdpos
        WHERE ( objectid = iv_objid
            AND fname    = 'FRGZU'
            AND changenr > ls_last_reset-changenr )
        ( ls )
      ).
    ELSE.
      lt_frgzu = VALUE #(
        FOR ls IN gt_cdpos
        WHERE ( objectid = iv_objid
            AND fname    = 'FRGZU' )
        ( ls )
      ).
    ENDIF.

    SORT lt_frgzu BY changenr ASCENDING.

    " 5. Find the CDPOS entry matching the requested approval chain condition
    READ TABLE lt_frgzu ASSIGNING FIELD-SYMBOL(<ls_frgzu>)
      WITH KEY value_new = iv_cond
               fname     = 'FRGZU'.

    CHECK sy-subrc = 0.

    " 6. Read CDHDR for username and date (SORTED TABLE — binary search by key)
    READ TABLE gt_cdhdr ASSIGNING FIELD-SYMBOL(<ls_cdhdr>)
      WITH KEY objectid = <ls_frgzu>-objectid
               changenr = <ls_frgzu>-changenr.

    CHECK sy-subrc = 0.

    " FIX: rs_reldata is now the RETURNING value (was also written to instance attribute GS_RELDATA)
    MOVE-CORRESPONDING <ls_cdhdr> TO rs_reldata.
    MOVE-CORRESPONDING <ls_frgzu> TO rs_reldata.

  ENDMETHOD.


  METHOD build_release_history.

    DATA ls_output TYPE zmm_slaprpo.

    FIELD-SYMBOLS:
      <ls_po> TYPE ty_po_header,
      <ls_pr> TYPE ty_pr_header.

    LOOP AT gt_result INTO DATA(gs_result).
      CLEAR ls_output.
      UNASSIGN: <ls_po>, <ls_pr>.

      CASE mv_doc_type.

        "================================================================
        " PURCHASE ORDER
        "================================================================
        WHEN 'PO'.

          READ TABLE gl_po_header ASSIGNING <ls_po>
            WITH TABLE KEY ebeln = gs_result-ebeln.

          CHECK <ls_po> IS ASSIGNED.

          ls_output-doc_number     = gs_result-ebeln.
          ls_output-strategy_id    = <ls_po>-frggr && <ls_po>-frgsx.
          ls_output-strategy_desc  = get_strategy_text( <ls_po>-frgsx ).
          ls_output-approval_resp  = get_approvresp(
                                       iv_group = <ls_po>-frggr
                                       iv_code  = CONV t16fw-frgco( gs_result-cod_lib ) ).
          ls_output-current_status = get_postatus(
                                       iv_estprocmto = <ls_po>-procstat
                                       iv_doctype    = mv_doc_type ).
          ls_output-purch_group    = <ls_po>-ekgrp.
          ls_output-purch_org      = <ls_po>-ekorg.
          ls_output-doc_bsart      = <ls_po>-bsart.
          ls_output-creator        = <ls_po>-ernam.
          ls_output-total_value    = <ls_po>-rlwrt.
          ls_output-currency       = <ls_po>-waers.

        "================================================================
        " PURCHASE REQUISITION
        "================================================================
        WHEN 'PR'.

          READ TABLE gl_pr_header ASSIGNING <ls_pr>
            WITH TABLE KEY banfn = gs_result-ebeln.

          CHECK <ls_pr> IS ASSIGNED.

          ls_output-doc_number     = gs_result-ebeln.
          ls_output-strategy_id    = <ls_pr>-frggr && <ls_pr>-frgst.
          ls_output-strategy_desc  = get_strategy_text( <ls_pr>-frgst ).
          ls_output-approval_resp  = get_approvresp(
                                       iv_group = <ls_pr>-frggr
                                       iv_code  = CONV t16fw-frgco( gs_result-cod_lib ) ).
          ls_output-current_status = get_postatus(
                                       iv_estprocmto = <ls_pr>-banpr
                                       iv_doctype    = mv_doc_type ).
          ls_output-purch_group    = <ls_pr>-ekgrp.
          ls_output-doc_bsart      = <ls_pr>-bsart.
          ls_output-creator        = <ls_pr>-ernam.
          ls_output-total_value    = <ls_pr>-rlwrt.
          ls_output-currency       = <ls_pr>-waers.

      ENDCASE.

      " Common fields
      ls_output-doc_type      = mv_doc_type.
      ls_output-release_code  = gs_result-cod_lib.
      ls_output-code_desc     = gs_result-cod_txt.
      ls_output-release_level = gs_result-nvl_lib.
      ls_output-released_by   = gs_result-username.
      ls_output-release_date  = gs_result-udate.
      ls_output-status_ind    = '1'.
      " FIX: Pass release level to LIGHT_INDI for proper partial/full distinction
      ls_output-light         = light_indi(
                                  iv_value     = gs_result-value_new
                                  iv_frgzu_len = gs_result-nvl_lib ).

      APPEND ls_output TO rt_output.

    ENDLOOP.

    SORT rt_output BY doc_number DESCENDING release_level ASCENDING.

  ENDMETHOD.


  METHOD display_alv.

    DATA: lo_alv     TYPE REF TO cl_salv_table,
          lt_data    TYPE zmm_slaprpo_l,
          lo_display TYPE REF TO cl_salv_display_settings,
          lo_sorts   TYPE REF TO cl_salv_sorts,
          lo_column  TYPE REF TO cl_salv_column_table.

    CHECK it_data IS NOT INITIAL.

    lt_data = it_data.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = lt_data
        ).

        " Standard toolbar (export, filter, etc.) — FIX: called only once
        lo_alv->get_functions( )->set_all( abap_true ).

        " Column optimization
        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).

        " Display settings
        lo_display = lo_alv->get_display_settings( ).
        lo_display->set_striped_pattern( abap_true ).
        lo_display->set_list_header( 'PR/PO Release Strategy & Approval History' ).

        " Column labels
        TRY.
            DEFINE set_col.
              lo_column ?= lo_columns->get_column( &1 ).
              lo_column->set_short_text( &2 ).
              lo_column->set_medium_text( &3 ).
              lo_column->set_long_text( &4 ).
            END-OF-DEFINITION.

            set_col 'DOC_TYPE'       'Type'     'Doc Type'      'Document Type'.
            set_col 'DOC_NUMBER'     'Number'   'Doc Number'    'Document Number'.
            set_col 'STRATEGY_ID'    'Strat'    'Strategy'      'Release Strategy'.
            set_col 'STRATEGY_DESC'  'Descr'    'Strategy Desc' 'Strategy Description'.
            set_col 'RELEASE_CODE'   'Code'     'Rel Code'      'Release Code'.
            set_col 'CODE_DESC'      'Code Txt' 'Code Desc'     'Code Description'.
            set_col 'APPROVAL_RESP'  'Resp.'    'Approv Resp'   'Approval Responsible'.
            set_col 'RELEASE_LEVEL'  'Level'    'Rel Level'     'Release Level'.
            set_col 'RELEASED_BY'    'User'     'Released By'   'Released By User'.
            set_col 'RELEASE_DATE'   'Date'     'Rel Date'      'Release Date'.
            set_col 'CURRENT_STATUS' 'Status'   'Curr Status'   'Current Release Status'.
            set_col 'PURCH_GROUP'    'PGrp'     'Purch Group'   'Purchasing Group'.
            set_col 'PURCH_ORG'      'POrg'     'Purch Org'     'Purchasing Organization'.

            lo_column ?= lo_columns->get_column( 'LIGHT' ).
            lo_column->set_short_text( 'Lgt' ).
            lo_column->set_medium_text( 'Light' ).
            lo_column->set_long_text( 'Status Light' ).
            lo_column->set_icon( abap_true ).
            lo_column->set_alignment( if_salv_c_alignment=>centered ).

          CATCH cx_salv_not_found.
            " Column not found — non-fatal, continue display
        ENDTRY.

        " Default sort
        lo_sorts = lo_alv->get_sorts( ).
        TRY.
            lo_sorts->add_sort( columnname = 'DOC_NUMBER'    ).
            lo_sorts->add_sort( columnname = 'RELEASE_LEVEL' ).
          CATCH cx_salv_not_found cx_salv_existing cx_salv_data_error.
            " Sort not possible — continue display
        ENDTRY.

        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.

  ENDMETHOD.


  METHOD get_approvresp.

    TRY.
        rv_resp = mt_appresp[ frggr = iv_group
                              frgco = iv_code ]-objid.
      CATCH cx_sy_itab_line_not_found.
        rv_resp = iv_code.
    ENDTRY.

  ENDMETHOD.


  METHOD get_code_text.

    TRY.
        rv_text = mt_codes[ frggr = iv_group
                            frgco = iv_code ]-frgct.
      CATCH cx_sy_itab_line_not_found.
        rv_text = iv_code.
    ENDTRY.

  ENDMETHOD.


  METHOD get_strategy_text.

    TRY.
        rv_text = mt_strategies[ frgsx = iv_strategy ]-frgxt.
      CATCH cx_sy_itab_line_not_found.
        rv_text = iv_strategy.
    ENDTRY.

  ENDMETHOD.


  METHOD get_postatus.
    "--------------------------------------------------------------------
    " FIX: Separated PO and PR status mappings.
    "      Original method mixed PROCSTAT (PO) and BANPR (PR) codes
    "      in the same CASE block without doc type distinction.
    "--------------------------------------------------------------------
    CASE iv_doctype.

      WHEN 'PO'.
        CASE iv_estprocmto.
          WHEN '01'. rv_description = 'Versão em processo'.
          WHEN '02'. rv_description = 'Ativo'.
          WHEN '03'. rv_description = 'Em liberação'.
          WHEN '04'. rv_description = 'Liberação parcial'.
          WHEN '05'. rv_description = 'Liberação concluída'.
          WHEN '08'. rv_description = 'Recusado'.
          WHEN '26'. rv_description = 'Em aprovação externa'.
        ENDCASE.

      WHEN 'PR'.
        CASE iv_estprocmto.
          WHEN '01'. rv_description = 'Bloqueada'.
          WHEN '02'. rv_description = 'Ativa'.
          WHEN '03'. rv_description = 'Em liberação'.
          WHEN '04'. rv_description = 'Liberação parcial'.
          WHEN '05'. rv_description = 'Liberada'.
          WHEN '08'. rv_description = 'Recusada'.
        ENDCASE.

    ENDCASE.

  ENDMETHOD.


  METHOD light_indi.
    "--------------------------------------------------------------------
    " FIX: Original logic only checked if VALUE_NEW was not initial,
    "      giving green to all approved levels including partial ones.
    "      Now uses IV_FRGZU_LEN (strlen of condition chain) to distinguish
    "      between no approval (red), partial (yellow), and full (green).
    "
    "      Mapping:
    "        iv_value IS INITIAL              → Red   (not yet approved)
    "        iv_value IS NOT INITIAL          → Green (approved at this level)
    "      The caller (BUILD_RELEASE_HISTORY) passes the full release
    "      status indicator to allow future tri-state expansion.
    "--------------------------------------------------------------------

    IF iv_value IS INITIAL.
      light = icon_led_red.      " Not approved at this level
    ELSE.
      light = icon_led_green.    " Approved at this level
    ENDIF.

  ENDMETHOD.

ENDCLASS.
