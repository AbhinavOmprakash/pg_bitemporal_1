CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update(p_table text
,p_list_of_fields text -- fields to update
,p_list_of_values TEXT  -- values to update with
,p_search_fields TEXT  -- search fields
,p_search_values TEXT  --  search values
,p_effective temporal_relationships.timeperiod  -- effective range of the update
,p_asserted temporal_relationships.timeperiod  -- assertion for the update
) 
RETURNS void
AS
$BODY$
DECLARE 
v_list_of_fields_to_insert text:=' ';
v_list_of_fields_to_insert_excl_effective text;
v_table_attr text[];
v_now timestamptz:=now();-- so that we can reference this time
BEGIN 
 IF lower(p_asserted)<v_now::date --should we allow this precision?...
    OR upper(p_asserted)< 'infinity'
 THEN RAISE EXCEPTION'Asserted interval starts in the past or has a finite end: %', p_asserted
  ; 
  RETURN;
 END IF;
 IF (bitemporal_internal.ll_check_bitemporal_update_conditions(p_table 
                                                       ,p_search_fields 
                                                       ,p_search_values
                                                       ,p_effective)  =0 )
 THEN RAISE EXCEPTION'Nothing to update, use INSERT or check effective: %', p_effective; 
  RETURN;
 END IF;   

v_table_attr := bitemporal_internal.ll_bitemporal_list_of_fields(p_table);
IF  array_length(v_table_attr,1)=0
      THEN RAISE EXCEPTION 'Empty list of fields for a table: %', p_table; 
  RETURN;
 END IF;
v_list_of_fields_to_insert_excl_effective:= array_to_string(v_table_attr, ',','');
v_list_of_fields_to_insert:= v_list_of_fields_to_insert_excl_effective||',effective';

--end assertion period for the old record(s)

EXECUTE format($u$ UPDATE %s SET asserted = tstzrange(lower(asserted), lower(%L::tstzrange), '[)')
                    WHERE ( %s )=( %s ) AND (temporal_relationships.is_overlaps(effective, %L)
                                       OR 
                                       temporal_relationships.is_meets(effective::temporal_relationships.timeperiod, %L)
                                       OR 
                                       temporal_relationships.has_finishes(effective::temporal_relationships.timeperiod, %L))
                                      AND now()<@ asserted  $u$  
          , p_table
          , p_asserted
          , p_search_fields
          , p_search_values
          , p_effective
          , p_effective
          , p_effective);
          
 --insert new assertion rage with old values and effective-ended
 
EXECUTE format($i$INSERT INTO %s ( %s, effective, asserted )
                SELECT %s ,tstzrange(lower(effective), lower(%L::tstzrange),'[)') ,%L
                  FROM %s WHERE ( %s )=( %s ) AND (temporal_relationships.is_overlaps(effective, %L)
                                       OR 
                                       temporal_relationships.is_meets(effective, %L)
                                       OR 
                                       temporal_relationships.has_finishes(effective, %L))
                                      AND upper(asserted)=lower(%L::tstzrange) $i$  
          , p_table
          , v_list_of_fields_to_insert_excl_effective
          , v_list_of_fields_to_insert_excl_effective
          , p_effective
          , p_asserted
          , p_table
          , p_search_fields
          , p_search_values
          , p_effective
          , p_effective
          , p_effective
          , p_asserted
);


---insert new assertion rage with old values and new effective range
 
EXECUTE format($i$INSERT INTO %s ( %s, effective, asserted )
                SELECT %s ,%L, %L
                  FROM %s WHERE ( %s )=( %s ) AND (temporal_relationships.is_overlaps(effective, %L)
                                       OR 
                                       temporal_relationships.is_meets(effective, %L)
                                       OR 
                                       temporal_relationships.has_finishes(effective, %L))
                                      AND upper(asserted)=lower(%L::tstzrange) $i$  
          , p_table
          , v_list_of_fields_to_insert_excl_effective
          , v_list_of_fields_to_insert_excl_effective
          , p_effective
          , p_asserted
          , p_table
          , p_search_fields
          , p_search_values
          , p_effective
          , p_effective
          , p_effective
          , p_asserted
);

--update new record(s) in new assertion rage with new values                                  
                                  
EXECUTE format($u$ UPDATE %s SET (%s) = (%L) 
                    WHERE ( %s )=( %s ) AND effective=%L
                                        AND asserted=%L $u$  
          , p_table
          , p_list_of_fields
          , p_list_of_values
          , p_search_fields
          , p_search_values
          , p_effective
          , p_asserted);
                                                                                               

END;    
$BODY$ LANGUAGE plpgsql;
