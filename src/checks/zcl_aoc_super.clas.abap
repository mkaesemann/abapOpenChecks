CLASS zcl_aoc_super DEFINITION
  PUBLIC
  INHERITING FROM cl_ci_test_scan
  ABSTRACT
  CREATE PUBLIC
  GLOBAL FRIENDS zcl_aoc_unit_test .

  PUBLIC SECTION.
    TYPE-POOLS zzaoc .

    TYPES:
      ty_structures_tt TYPE STANDARD TABLE OF sstruc WITH NON-UNIQUE DEFAULT KEY .

    METHODS constructor .
    METHODS check
      IMPORTING
        !io_scan TYPE REF TO zcl_aoc_scan .
    CLASS-METHODS get_destination
      RETURNING
        VALUE(rv_result) TYPE rfcdest .
    METHODS set_source
      IMPORTING
        !iv_name TYPE level_name
        !it_code TYPE string_table .

    METHODS get_attributes
        REDEFINITION .
    METHODS if_ci_test~display_documentation
        REDEFINITION .
    METHODS if_ci_test~query_attributes
        REDEFINITION .
    METHODS put_attributes
        REDEFINITION .
    METHODS run
        REDEFINITION .
  PROTECTED SECTION.

    TYPES:
      BEGIN OF ty_destination_cache,
        srcid   TYPE sysuuid_x,
        rfcdest TYPE rfcdest,
      END OF ty_destination_cache .
    TYPES ty_scimessage_text TYPE c LENGTH 255.

    DATA mv_errty TYPE sci_errty .
    CLASS-DATA gs_destination_cache TYPE ty_destination_cache .

    METHODS enable_rfc .
    METHODS get_source
      IMPORTING
        !is_level      TYPE slevel
      RETURNING
        VALUE(rt_code) TYPE string_table .
    METHODS is_class_pool
      IMPORTING
        !iv_include    TYPE level_name
      RETURNING
        VALUE(rv_bool) TYPE abap_bool .
    METHODS is_class_definition
      IMPORTING
        !iv_include    TYPE level_name
      RETURNING
        VALUE(rv_bool) TYPE abap_bool .
    METHODS is_generated
      IMPORTING
        !iv_name            TYPE csequence OPTIONAL
      RETURNING
        VALUE(rv_generated) TYPE abap_bool .
    METHODS enable_checksum.
    METHODS is_checksum_enabled
      RETURNING
        VALUE(rv_enabled) TYPE abap_bool.
    METHODS insert_scimessage
      IMPORTING
        !iv_code TYPE scimessage-code
        !iv_text TYPE ty_scimessage_text
        !iv_pcom TYPE scimessage-pcom OPTIONAL .
    METHODS has_pseudo_comment
      IMPORTING
        !i_comment              TYPE scimessage-pcom
        !is_statement           TYPE sstmnt
      RETURNING
        VALUE(r_comment_exists) TYPE abap_bool.

    METHODS inform
        REDEFINITION .
  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_source,
        name TYPE level_name,
        code TYPE string_table,
      END OF ty_source .
    TYPES:
      ty_source_tt TYPE SORTED TABLE OF ty_source WITH UNIQUE KEY name .

    DATA mt_source TYPE ty_source_tt.
    DATA mv_uses_checksum TYPE abap_bool.

    METHODS check_class
      IMPORTING
        !iv_sub_obj_name TYPE sobj_name
      RETURNING
        VALUE(rv_skip)   TYPE abap_bool .
    METHODS check_wdy
      IMPORTING
        !iv_sub_obj_type TYPE trobjtype
        !iv_sub_obj_name TYPE sobj_name
        !iv_line         TYPE token_row
      RETURNING
        VALUE(rv_skip)   TYPE abap_bool .
    METHODS get_checksum
      IMPORTING
        !iv_position       TYPE int4
      RETURNING
        VALUE(rv_checksum) TYPE int4.
    METHODS set_uses_checksum
      IMPORTING
        !iv_enable TYPE abap_bool DEFAULT abap_true.

ENDCLASS.



CLASS ZCL_AOC_SUPER IMPLEMENTATION.


  METHOD check.

* add code here
    ASSERT 0 = 1.

  ENDMETHOD.


  METHOD check_class.

    DATA: lv_category TYPE seoclassdf-category,
          lv_proxy    TYPE seoclassdf-clsproxy,
          lv_abstract TYPE seoclassdf-clsabstrct,
          lv_super    TYPE seometarel-refclsname,
          ls_mtdkey   TYPE seocpdkey.


    IF object_type <> 'CLAS'
        AND object_type <> 'INTF'.
      RETURN.
    ENDIF.

    SELECT SINGLE category clsproxy clsabstrct FROM seoclassdf
      INTO (lv_category, lv_proxy, lv_abstract)
      WHERE clsname = object_name
      AND version = '1'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

* skip persistent co-classes and web dynpro runtime objects
    IF lv_category = seoc_category_p_agent
        OR lv_category = seoc_category_webdynpro_class
        OR lv_proxy = abap_true.
      rv_skip = abap_true.
      RETURN.
    ENDIF.

* skip constructor in exception classes
    IF lv_category = seoc_category_exception.
      cl_oo_classname_service=>get_method_by_include(
        EXPORTING
          incname             = iv_sub_obj_name
        RECEIVING
          mtdkey              = ls_mtdkey
        EXCEPTIONS
          class_not_existing  = 1
          method_not_existing = 2
          OTHERS              = 3 ).
      IF sy-subrc = 0 AND ls_mtdkey-cpdname = 'CONSTRUCTOR'.
        rv_skip = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

* skip BOPF constants interfaces
    IF object_type = 'INTF' AND object_name CP '*_C'.
      SELECT SINGLE refclsname FROM seometarel INTO lv_super
        WHERE clsname = object_name
        AND reltype = '0'.                                                      "#EC CI_NOORDER
      IF sy-subrc = 0 AND lv_super = '/BOBF/IF_LIB_CONSTANTS'.
        rv_skip = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

* skip classes generated by Gateway Builder/SEGW
    IF ( lv_abstract = abap_true AND object_name CP '*_DPC' )
        OR object_name CP '*_MPC'.                                              "#EC CI_NOORDER
      SELECT SINGLE refclsname FROM seometarel INTO lv_super
        WHERE clsname = object_name AND reltype = '2'.
      IF sy-subrc = 0
          AND ( lv_super = '/IWBEP/CL_MGW_PUSH_ABS_MODEL'
          OR lv_super = '/IWBEP/CL_MGW_PUSH_ABS_DATA' ).
        rv_skip = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

* skip objects generated by SADL toolkit
    IF lv_super = 'CL_SADL_GTK_EXPOSURE_MPC'.
      rv_skip = abap_true.
    ENDIF.

  ENDMETHOD.


  METHOD check_wdy.

    DATA: ls_map_header TYPE wdy_wb_sourcemap,
          lo_tool_state TYPE REF TO cl_wdy_wb_vc_state,
          lv_inclname   TYPE program,
          ls_controller TYPE wdy_controller_key,
          lt_map        TYPE wdyrt_line_info_tab_type,
          lv_no_codepos TYPE seu_bool.


    IF iv_sub_obj_type <> 'PROG' OR iv_sub_obj_name(8) <> '/1BCWDY/'.
      RETURN.
    ENDIF.

    lv_inclname = iv_sub_obj_name.
    CALL FUNCTION 'WDY_WB_GET_SOURCECODE_MAPPING'
      EXPORTING
        p_include = lv_inclname
      IMPORTING
        p_map     = lt_map
        p_header  = ls_map_header
      EXCEPTIONS
        OTHERS    = 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ls_controller-component_name  = ls_map_header-component_name.
    ls_controller-controller_name = ls_map_header-controller_name.
    cl_wdy_wb_error_handling=>create_tool_state_for_codepos(
      EXPORTING
        p_controller_key           = ls_controller
        p_controller_type          = ls_map_header-ctrl_type
        p_line                     = iv_line
        p_lineinfo                 = lt_map
      IMPORTING
        p_no_corresponding_codepos = lv_no_codepos
        p_tool_state               = lo_tool_state ).
    IF lv_no_codepos = abap_true OR lo_tool_state IS INITIAL.
      rv_skip = abap_true.
    ENDIF.

  ENDMETHOD.


  METHOD constructor.
    super->constructor( ).

    "get description of check class
    SELECT SINGLE descript FROM seoclasstx INTO description
      WHERE clsname = myname
      AND langu   = sy-langu.
    IF sy-subrc <> 0.
      SELECT SINGLE descript FROM seoclasstx INTO description
        WHERE clsname = myname.                                                 "#EC CI_NOORDER "#EC CI_SUBRC
    ENDIF.

    category = 'ZCL_AOC_CATEGORY'.
    mv_errty = 'E'.

  ENDMETHOD.


  METHOD enable_checksum.
    mv_uses_checksum = abap_true.
  ENDMETHOD.


  METHOD enable_rfc.
* RFC enable the check, new feature for central ATC on 7.51

    FIELD-SYMBOLS: <lv_rfc> TYPE abap_bool.


    ASSIGN ('REMOTE_RFC_ENABLED') TO <lv_rfc>.
    IF sy-subrc = 0.
      <lv_rfc> = abap_true.
    ENDIF.

  ENDMETHOD.


  METHOD get_attributes.

    EXPORT mv_errty = mv_errty TO DATA BUFFER p_attributes.

  ENDMETHOD.


  METHOD get_checksum.

    DATA: ls_statement TYPE sstmnt,
          ls_checksum  TYPE sci_crc64.

    IF is_checksum_enabled( ) = abap_false.
      RETURN.
    ENDIF.

    IF ref_scan IS INITIAL.
      rv_checksum = 123456. " running as unit test, return fixed checksum
      RETURN.
    ENDIF.

    READ TABLE ref_scan->statements INDEX iv_position  INTO ls_statement.

    IF sy-subrc <> 0.
      set_uses_checksum( abap_false ).
    ELSE.

      TRY.
* parameter "p_version" does not exist in 751
* value p_version = '2' does not exist in 752
          CALL METHOD ('GET_STMT_CHECKSUM')
            EXPORTING
              p_position = iv_position
            CHANGING
              p_checksum = ls_checksum
            EXCEPTIONS
              error      = 0.
        CATCH cx_sy_dyn_call_illegal_method cx_sy_dyn_call_param_not_found.
          RETURN.
      ENDTRY.

      rv_checksum = ls_checksum-i1.

    ENDIF.

  ENDMETHOD.


  METHOD get_destination.

    "get destination of calling system (RFC enabled checks only)
    "class, method and variable may not valid in 7.02 systems -> dynamic calls

    FIELD-SYMBOLS: <lv_srcid> TYPE sysuuid_x.

    ASSIGN ('SRCID') TO <lv_srcid>.

    IF NOT <lv_srcid> IS ASSIGNED OR <lv_srcid> IS INITIAL.
      rv_result = |NONE|.
      RETURN.
    ENDIF.

    IF gs_destination_cache-srcid = <lv_srcid>.
      rv_result = gs_destination_cache-rfcdest.
      RETURN.
    ENDIF.

    TRY.
        CALL METHOD ('CL_ABAP_SOURCE_ID')=>('GET_DESTINATION')
          EXPORTING
            p_srcid       = <lv_srcid>
          RECEIVING
            p_destination = rv_result
          EXCEPTIONS
            not_found     = 1.
        IF sy-subrc <> 0.
          rv_result = |NONE|.
        ELSE.
* database table SCR_SRCID is not buffered, so buffer it here
          gs_destination_cache-srcid = <lv_srcid>.
          gs_destination_cache-rfcdest = rv_result.
        ENDIF.

      CATCH cx_sy_dyn_call_illegal_class
            cx_sy_dyn_call_illegal_method.
        rv_result = |NONE|.
    ENDTRY.

  ENDMETHOD.


  METHOD get_source.

    DATA: ls_source      LIKE LINE OF mt_source,
          lt_source      TYPE STANDARD TABLE OF abaptxt255 WITH DEFAULT KEY,
          lv_destination TYPE rfcdest.

    FIELD-SYMBOLS: <ls_source> LIKE LINE OF mt_source.


    IF is_level-type = zcl_aoc_scan=>gc_level-macro_define
        OR is_level-type = zcl_aoc_scan=>gc_level-macro_trmac.
      RETURN.
    ENDIF.

    READ TABLE mt_source ASSIGNING <ls_source> WITH KEY name = is_level-name.
    IF sy-subrc = 0.
      rt_code = <ls_source>-code.
    ELSE.
      lv_destination = get_destination( ).

      CALL FUNCTION 'RPY_PROGRAM_READ'
        DESTINATION lv_destination
        EXPORTING
          program_name     = is_level-name
          with_includelist = abap_false
          only_source      = abap_true
          with_lowercase   = abap_true
        TABLES
          source_extended  = lt_source
        EXCEPTIONS
          cancelled        = 1
          not_found        = 2
          permission_error = 3
          OTHERS           = 4.
      ASSERT sy-subrc = 0.

      rt_code = lt_source.

      ls_source-name = is_level-name.
      ls_source-code = rt_code.
      INSERT ls_source INTO TABLE mt_source.
    ENDIF.

  ENDMETHOD.


  METHOD if_ci_test~display_documentation.

    DATA: lv_url    TYPE string VALUE 'http://docs.abapopenchecks.org/checks/' ##NO_TEXT,
          lt_string TYPE STANDARD TABLE OF string,
          lv_num    TYPE string,
          lv_lines  TYPE i.

    SPLIT myname AT '_' INTO TABLE lt_string.

    lv_lines = lines( lt_string ).

    READ TABLE lt_string INTO lv_num INDEX lv_lines.

    CONCATENATE lv_url lv_num INTO lv_url.

    cl_gui_frontend_services=>execute(
      EXPORTING
        document               = lv_url
      EXCEPTIONS
        cntl_error             = 1
        error_no_gui           = 2
        bad_parameter          = 3
        file_not_found         = 4
        path_not_found         = 5
        file_extension_unknown = 6
        error_execute_failed   = 7
        synchronous_failed     = 8
        not_supported_by_gui   = 9
        OTHERS                 = 10 ).                    "#EC CI_SUBRC

  ENDMETHOD.


  METHOD if_ci_test~query_attributes.

    zzaoc_top.

    zzaoc_fill_att mv_errty 'Error Type' ''.                                    "#EC NOTEXT

    zzaoc_popup.

  ENDMETHOD.


  METHOD inform.

    DATA: lv_cnam         TYPE reposrc-cnam,
          lv_area         TYPE tvdir-area,
          lv_skip         TYPE abap_bool,
          lv_sub_obj_type LIKE p_sub_obj_type,
          lv_line         LIKE p_line,
          lv_column       LIKE p_column,
          lv_checksum_1   TYPE int4.

    FIELD-SYMBOLS: <ls_message> LIKE LINE OF scimessages.


    lv_sub_obj_type = p_sub_obj_type.
    IF lv_sub_obj_type IS INITIAL AND NOT p_sub_obj_name IS INITIAL.
      lv_sub_obj_type = 'PROG'.
    ENDIF.

    IF lv_sub_obj_type = 'PROG' AND p_sub_obj_name <> ''.
      IF p_sub_obj_name CP 'MP9+++BI' OR p_sub_obj_name CP 'MP9+++00'.
        RETURN. " custom HR infotype includes
      ENDIF.

*      IF cl_enh_badi_def_utility=>is_sap_system( ) = abap_false.
*        SELECT SINGLE cnam FROM reposrc INTO lv_cnam
*          WHERE progname = p_sub_obj_name AND r3state = 'A'.
*        IF sy-subrc = 0
*            AND ( lv_cnam = 'SAP'
*            OR lv_cnam = 'SAP*'
*            OR lv_cnam = 'DDIC' ).
*          RETURN.
*        ENDIF.
*      ENDIF.
    ENDIF.

    IF object_type = 'SSFO'
        AND lv_sub_obj_type = 'PROG'
        AND ( p_sub_obj_name CP '/1BCDWB/LSF*'
        OR p_sub_obj_name CP '/1BCDWB/SAPL*' ).
      RETURN.
    ENDIF.

    IF object_type = 'FUGR'.
      IF p_sub_obj_name CP 'LY*UXX'
          OR p_sub_obj_name CP 'LZ*UXX'
          OR zcl_aoc_util_reg_atc_namespace=>is_registered_fugr_uxx( p_sub_obj_name ) = abap_true.
        RETURN.
      ENDIF.
      SELECT SINGLE area FROM tvdir INTO lv_area
        WHERE area = object_name ##WARN_OK.                                     "#EC CI_GENBUFF
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
    ENDIF.

    lv_skip = check_class( p_sub_obj_name ).
    IF lv_skip = abap_true.
      RETURN.
    ENDIF.

    lv_skip = check_wdy( iv_sub_obj_type = lv_sub_obj_type
                         iv_sub_obj_name = p_sub_obj_name
                         iv_line         = p_line ).
    IF lv_skip = abap_true.
      RETURN.
    ENDIF.

    READ TABLE scimessages ASSIGNING <ls_message>
      WITH KEY test = myname code = p_code.
    IF sy-subrc = 0.
      <ls_message>-kind = p_kind.
    ENDIF.
    IF sy-subrc = 0 AND NOT mt_source IS INITIAL.
      READ TABLE mt_source
        WITH KEY name = '----------------------------------------'
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0 AND lines( mt_source ) = 1.
* fix failing unit tests
        CLEAR <ls_message>-pcom.
      ENDIF.
    ENDIF.

    " Determine line and column, if empty.
    " Findings in macros for example are reported with line 0.
    " This leads to problems with the filter for findings in SAP standard code.
    " We need to find the calling statement and point to this line.
    lv_line   = p_line.
    lv_column = p_column.
    IF ( lv_line = 0 OR lv_column = 0 ) AND p_position <> 0 AND NOT ref_scan IS INITIAL.
      READ TABLE ref_scan->statements INTO statement_wa INDEX p_position.
      IF sy-subrc = 0.
        get_line_column_rel(
          EXPORTING
            p_n      = 1
          IMPORTING
            p_line   = lv_line
            p_column = lv_column ).
      ENDIF.
    ENDIF.

    set_uses_checksum( is_checksum_enabled( ) ).

    IF sy-subrc = 0 AND p_checksum_1 IS NOT INITIAL.
      lv_checksum_1 = p_checksum_1.
    ELSE.
      lv_checksum_1 = get_checksum( p_position ).
    ENDIF.

    super->inform(
      p_sub_obj_type = lv_sub_obj_type
      p_sub_obj_name = p_sub_obj_name
      p_position     = p_position
      p_line         = lv_line
      p_column       = lv_column
      p_errcnt       = p_errcnt
      p_kind         = p_kind
      p_test         = p_test
      p_code         = p_code
      p_suppress     = p_suppress
      p_param_1      = p_param_1
      p_param_2      = p_param_2
      p_param_3      = p_param_3
      p_param_4      = p_param_4
      p_inclspec     = p_inclspec
      p_detail       = p_detail
      p_checksum_1   = lv_checksum_1 ).

    set_uses_checksum( is_checksum_enabled( ) ).

  ENDMETHOD.


  METHOD insert_scimessage.

* Insert entry into table scimessages, this table is used to determine the message text for a finding.
    DATA ls_scimessage LIKE LINE OF scimessages.

    ls_scimessage-test = myname.
    ls_scimessage-code = iv_code.
    ls_scimessage-kind = mv_errty.
    ls_scimessage-text = iv_text.
    ls_scimessage-pcom = iv_pcom.

    INSERT ls_scimessage INTO TABLE scimessages.

  ENDMETHOD.


  METHOD is_checksum_enabled.
    rv_enabled = mv_uses_checksum.
  ENDMETHOD.


  METHOD is_class_definition.

    IF strlen( iv_include ) = 32
        AND ( object_type = 'CLAS' OR object_type = 'INTF' )
        AND ( iv_include+30(2) = 'CO'
        OR iv_include+30(2) = 'CI'
        OR iv_include+30(2) = 'CU'
        OR iv_include+30(2) = 'IU' ).
      rv_bool = abap_true.
    ELSE.
      rv_bool = abap_false.
    ENDIF.

  ENDMETHOD.


  METHOD is_class_pool.

    IF strlen( iv_include ) = 32
        AND ( ( object_type = 'CLAS'
        AND iv_include+30(2) = 'CP' )
        OR ( object_type = 'INTF'
        AND iv_include+30(2) = 'IP' ) ).
      rv_bool = abap_true.
    ELSE.
      rv_bool = abap_false.
    ENDIF.

  ENDMETHOD.


  METHOD is_generated.

    DATA lv_genflag TYPE tadir-genflag.

    SELECT SINGLE genflag
      FROM tadir
      INTO lv_genflag
      WHERE pgmid    = 'R3TR'
        AND object   = object_type
        AND obj_name = object_name
        AND genflag  = abap_true.
    rv_generated = boolc( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD put_attributes.

    IMPORT
      mv_errty = mv_errty
      FROM DATA BUFFER p_attributes.                                            "#EC CI_USE_WANTED
    ASSERT sy-subrc = 0.

  ENDMETHOD.


  METHOD run.

* abapOpenChecks
* https://github.com/larshp/abapOpenChecks
* MIT License

    CLEAR mt_source.  " limit memory use

    IF program_name IS INITIAL.
      RETURN.
    ENDIF.
    IF ref_scan IS INITIAL AND get( ) <> abap_true.
      RETURN.
    ENDIF.

    IF is_generated( ) = abap_true.
      RETURN.
    ENDIF.

    IF ref_include IS BOUND.
* ref_include is not set when running checks via RFC
      set_source( iv_name = ref_include->trdir-name
                  it_code = ref_include->lines ).
    ENDIF.

    check( zcl_aoc_scan=>create_from_ref( ref_scan ) ).

  ENDMETHOD.


  METHOD set_source.

* used for unit testing

    DATA: ls_source LIKE LINE OF mt_source.


    ls_source-name = iv_name.
    ls_source-code = it_code.

    INSERT ls_source INTO TABLE mt_source.

  ENDMETHOD.


  METHOD set_uses_checksum.
* Activate checksum for current check, new feature for central ATC on 7.51

    FIELD-SYMBOLS: <lv_uses_checksum> TYPE abap_bool.

    IF is_checksum_enabled( ) = abap_false.
      RETURN.
    ENDIF.

    ASSIGN ('USES_CHECKSUM') TO <lv_uses_checksum>.
    IF sy-subrc = 0.
      <lv_uses_checksum> = iv_enable.
    ENDIF.

  ENDMETHOD.


  METHOD has_pseudo_comment.

    r_comment_exists = abap_false.

    LOOP AT ref_scan->statements TRANSPORTING NO FIELDS
      WHERE table_line = is_statement.
      DATA(statement_index) = sy-tabix.
      DATA(prev_statement_index) = sy-tabix - 1.
      DATA(next_statement_index) = sy-tabix + 1.
      EXIT.
    ENDLOOP.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(from) = is_statement-from.
    DATA(to)   = is_statement-to.

    "Check if we need to incorporate the surrounding area
    READ TABLE ref_scan->statements INTO DATA(ls_statement)
      INDEX prev_statement_index.
    IF sy-subrc = 0 AND
       ( ls_statement-type = zcl_aoc_scan=>gc_statement-comment OR
         ls_statement-type = zcl_aoc_scan=>gc_statement-comment_in_stmnt ) AND
         ls_statement-from < from.
      "Preceding Statement has a comment
      from = ls_statement-from.
    ENDIF.
    READ TABLE ref_scan->statements INTO ls_statement
      INDEX next_statement_index.
    IF sy-subrc = 0 AND
       ( ls_statement-type = zcl_aoc_scan=>gc_statement-comment OR
         ls_statement-type = zcl_aoc_scan=>gc_statement-comment_in_stmnt ) AND
         ls_statement-to > to.
      "Preceding Statement has a comment
      to = ls_statement-to.
    ENDIF.

    "Check Comment Statement
    LOOP AT ref_scan->tokens INTO DATA(ls_token)
      FROM from TO to.
      IF ( ls_token-type = zcl_aoc_scan=>gc_token-comment AND
           ( ls_token-str = |"#EC { to_upper( i_comment ) }| or
             ls_token-str = |"#EC *| ) ).
        r_comment_exists = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
