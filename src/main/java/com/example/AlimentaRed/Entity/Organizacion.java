package com.example.AlimentaRed.Entity;

import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "organizacion")

public class Organizacion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idOrganizacion;

    @Column(nullable = false, unique = true)
    private Integer nit;

    @Column(nullable = false)
    private String nombre;

    private String ubicacion;

    @Column(nullable = false)
    private String correo;

    private String telefono;
}